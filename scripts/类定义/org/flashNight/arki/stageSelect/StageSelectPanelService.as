import org.flashNight.arki.stageSelect.StageAdmissionBridge;
import org.flashNight.arki.scene.StageRunSession;

/**
 * 文件：org/flashNight/arki/stageSelect/StageSelectPanelService.as
 * 说明：WebView 选关面板测试入口的真实进关桥。
 */
class org.flashNight.arki.stageSelect.StageSelectPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _pendingEnterResponseContexts:Object = {};
    private static var _committedEnterResponseContext:Object = null;

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};

        _root.gameCommands["stageSelectSnapshot"] = function(params) {
            org.flashNight.arki.stageSelect.StageSelectPanelService.handleSnapshot(params);
        };
        _root.gameCommands["stageSelectEnter"] = function(params) {
            org.flashNight.arki.stageSelect.StageSelectPanelService.handleEnter(params);
        };
        _root.gameCommands["stageSelectOutcome"] = function(params):Void {
            var state:String = StageAdmissionBridge.statusFor("panel."+params.callId);
            var success:Boolean = state == "committed" || state == "started";
            sendResponse({task:"stage_select_response", callId:params.callId, success:success,
                closePanel:success, error:state == "failed" ? "stage_transition_failed" : "stage_delivery_unknown"});
        };
        _root.gameCommands["stageSelectJumpFrame"] = function(params) {
            org.flashNight.arki.stageSelect.StageSelectPanelService.handleJumpFrame(params);
        };
        _root.gameCommands["stageSelectReturnFrame"] = function(params) {
            org.flashNight.arki.stageSelect.StageSelectPanelService.handleReturnFrame(params);
        };
        _root.gameCommands["stageSelectPanelClose"] = function(params) {
            org.flashNight.arki.stageSelect.StageSelectPanelService.handleClose(params);
        };
        _root.gameCommands["openWebStageSelect"] = function(params) {
            return org.flashNight.arki.stageSelect.StageSelectPanelService.handleOpenWebStageSelect(params);
        };
        _root.gameCommands["openArenaForAgent"] = function(params) {
            return org.flashNight.arki.stageSelect.StageSelectPanelService.handleOpenArenaForAgent(params);
        };

        _inited = true;
    }

    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        var requestedFrameLabel:String = params != undefined && params.frameLabel != undefined
            ? resolveStageSelectFrameLabel(String(params.frameLabel))
            : "";
        var requestedReturnFrameLabel:String = params != undefined && params.returnFrameLabel != undefined
            ? resolveRootReturnFrameLabel(String(params.returnFrameLabel))
            : "";
        var challengeActive:Boolean = isChallengeMode();
        if (params != undefined && params.setForceUnlock != undefined) {
            if (challengeActive) {
                _root.Web选关强制解锁 = false;
            } else {
                _root.Web选关强制解锁 = (params.setForceUnlock == true || params.setForceUnlock == "true" || params.setForceUnlock == 1);
            }
        } else if (challengeActive && _root.Web选关强制解锁 == true) {
            _root.Web选关强制解锁 = false;
        }
        var names:Array = normalizeStageNames(params.stageNames);
        if (requestedFrameLabel != "") _root.Web选关当前帧值 = requestedFrameLabel;
        if (requestedReturnFrameLabel != "") _root.Web选关返回帧值 = requestedReturnFrameLabel;
        StageAdmissionBridge.request(names, "panel", "", StageAdmissionBridge.nextId(), "panel."+callId,
            false, null, function(result:Object, error:String):Void {
                org.flashNight.arki.stageSelect.StageSelectPanelService.publishSnapshot(callId, names, result, error);
            });
    }

    private static function failure(callId, error:String):Void {
        sendResponse({task:"stage_select_response", callId:callId, success:false, error:error});
    }

    private static function publishSnapshot(callId, names:Array, result:Object, error:String):Void {
        if (result == null) { failure(callId, error); return; }
        var unlocked:Object = {}, nativeUnlocked:Object = {}, details:Object = {};
        for (var i:Number = 0; i < names.length; i++) {
            var name:String = names[i];
            var decision:Object = result.decisions[name];
            unlocked[name] = decision.unlocked === true;
            nativeUnlocked[name] = decision.nativeUnlocked === true;
            details[name] = buildStageDetail(name, String(decision.reason || ""));
        }
        sendResponse({task:"stage_select_response", callId:callId, success:true, snapshot:{
            unlockedStages:unlocked, nativeUnlockedStages:nativeUnlocked, stageDetails:details,
            admissionCatalog:result.catalog, forceUnlock:result.force, isChallengeMode:result.challenge,
            currentFrameLabel:resolveStageSelectFrameLabel(String(_root.Web选关当前帧值 || _root.关卡地图帧值 || "")),
            returnFrameLabel:resolveRootReturnFrameLabel(String(_root.Web选关返回帧值 || _root.关卡地图帧值 || ""))}});
    }

    public static function handleEnter(params:Object):Void {
        var name:String = String(params.stageName || "");
        var mode:String = String(params.difficulty || "");
        var kind:String = String(params.entryKind || "difficulty");
        var validation:Object = validateEnter(name, mode, kind);
        if (validation.success !== true) { failure(params.callId, String(validation.error)); return; }
        var ordinary:Boolean = kind == "difficulty" && name != "DEATH MATCH角斗场";
        var busy:String = kind == "map" ? StageRunSession.getSceneExitBlockReason() : StageRunSession.getStageStartBlockReason();
        if (busy != "") { failure(params.callId, "pending_stage_settlement"); return; }
        var id:String = ordinary ? StageRunSession.reserveStageStart("stage_select", name, mode) : StageAdmissionBridge.nextId();
        if (id == "") { failure(params.callId, "pending_stage_settlement"); return; }
        var ticket:Object = {callId:params.callId, id:id, name:name, mode:mode, kind:kind,
            ordinary:ordinary, context:validation.context};
        var guard:Function = function():Boolean {
            return ticket.ordinary ? StageRunSession.matchesStageStartReservation(ticket.id, "stage_select", ticket.name)
                : StageRunSession.getSceneExitBlockReason() == "";
        };
        StageAdmissionBridge.request([name],kind,mode,id,"panel."+params.callId,true,guard,
            function(grant:Object, error:String):Void {
                org.flashNight.arki.stageSelect.StageSelectPanelService.applyGrant(ticket, grant, error);
            });
    }

    private static function applyGrant(ticket:Object, grant:Object, error:String):Void {
        if (grant == null || (!ticket.ordinary && !StageAdmissionBridge.seal(grant))) {
            if (ticket.ordinary) StageRunSession.cancelStageStart(ticket.id);
            StageAdmissionBridge.outcome(grant, "failed");
            failure(ticket.callId, error || "stage_state_changed"); return;
        }
        if (ticket.ordinary) {
            performEnter(ticket.name, ticket.context, ticket.name, ticket.mode, ticket.kind, ticket.id, ticket.callId, grant);
            return;
        }
        var result:Object;
        if (ticket.kind == "map") result = performMapEnter(ticket.context.stageInfo);
        else if (ticket.kind == "task") {
            var task:Object = _root.getTaskData(ticket.name);
            result = {success:task.id != null && _root.gameCommands.openWebDungeon({taskId:task.id}) === true,
                redirected:"tasks-dungeon", error:"task_ui_unavailable"};
        } else result = {success:requestOpenArenaPanel(ticket.mode), redirected:"arena", error:"arena_ui_unavailable"};
        StageAdmissionBridge.outcome(grant, result.success === true ? "committed" : "failed");
        if (result.success !== true) { failure(ticket.callId, String(result.error)); return; }
        cleanupStageSelectState();
        sendResponse({task:"stage_select_response", callId:ticket.callId, success:true, closePanel:ticket.kind=="map",
            stageName:ticket.name, difficulty:ticket.mode, entryKind:ticket.kind, redirected:result.redirected});
    }

    /** Shared executor for fixed special destinations and old SWFs. Ignore caller-supplied URL/fade/globals. */
    public static function enterFromWorld(name:String, mode:String, kind:String, owner:String, callback:Function):Boolean {
        var info:Object = _root.StageInfoDict[name];
        if (info == null || !isDifficultyStageType(String(info.Type)) || !isValidDifficulty(mode)
                || typeof _root.配置关卡属性 != "function") { callback(false, "stage_config_unavailable"); return false; }
        var context:Object = {};
        context.configure = _root.配置关卡属性;
        context.configure(name);
        var id:String = StageRunSession.reserveStageStart("stage_select", name, mode);
        if (id == "") { callback(false, "pending_stage_settlement"); return false; }
        var guard:Function = function():Boolean { return StageRunSession.matchesStageStartReservation(id, "stage_select", name); };
        StageAdmissionBridge.request([name],kind,mode,id,owner,true,guard,function(grant:Object,error:String):Void {
            if (grant == null) { StageRunSession.cancelStageStart(id); callback(false,error); return; }
            org.flashNight.arki.stageSelect.StageSelectPanelService.performEnter(name,context,name,mode,kind,id,0,grant,callback);
        });
        return true;
    }

    /** Old diplomatic map buttons have their own MovieClip owner and never use the Web force switch. */
    public static function configureLegacyMap(clip:Object, info:Object):Void {
        var name:String = String(info.Name);
        var identity:String = StageAdmissionBridge.nextId();
        clip.__admissionOwner = identity;
        clip._visible = false;
        clip.onPress = null;
        var guard:Function = function():Boolean {
            return clip.__admissionOwner === identity && clip._parent != undefined
                && StageRunSession.getSceneExitBlockReason() == "";
        };
        StageAdmissionBridge.request([name], "legacy_map", "", identity, "legacy."+identity, false, guard,
            function(result:Object, error:String):Void {
                if (result == null || !guard() || result.decisions[name].nativeUnlocked !== true) return;
                _root.配置基础关卡信息(clip, info);
                clip._visible = true;
                clip.onPress = function():Void {
                    if (!guard()) return;
                    StageAdmissionBridge.request([name], "legacy_map", "", StageAdmissionBridge.nextId(), "legacy."+identity,
                        true, guard, function(grant:Object, why:String):Void {
                            if (grant == null) return;
                            var ok:Boolean = StageAdmissionBridge.seal(grant)
                                && org.flashNight.arki.stageSelect.StageSelectPanelService.performMapEnter(info).success === true;
                            StageAdmissionBridge.outcome(grant, ok ? "committed" : "failed");
                        });
                };
            });
    }

    /**
     * 通知 C# LauncherCommandRouter 打开 arena panel。
     * 与 handleOpenWebStageSelect 同模式：走 panel_request 协议。
     * 由 LauncherCommandRouter.RequestOpenPanel("arena", ...) 接管，PanelHostController
     * 内部会先 DoClose 当前 stage-select 再 DoOpen arena，所以这里不需要管 panel 切换时序。
     *
     * 字段说明：
     *   - initData.difficulty: 让 arena enter 时能回传给 AS2 设 _root.当前关卡难度，
     *                          否则任务系统 FinishStage 拿不到难度导致 "stage#冒险" 不匹配。
     *   - returnTo: 声明"关闭 arena 后回到 stage-select"。携带 returnFrameLabel/frameLabel
     *               让 PanelHostController 在 pop 栈时用对应 initData 重开 stage-select。
     */
    private static function requestOpenArenaPanel(difficulty:String):Boolean {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return false;
        var frameLabel:String = String(_root.Web选关当前帧值 || _root.关卡地图帧值 || "基地门口");
        var returnFrameLabel:String = String(_root.Web选关返回帧值 || _root.关卡地图帧值 || frameLabel);
        return _root.server.sendSocketMessage(_json.stringifySafe({
            task: "panel_request",
            panel: "arena",
            source: "stage_select_arena_redirect",
            initData: {
                difficulty: String(difficulty || "")
            },
            returnTo: "stage-select",
            returnToInitData: {
                mode: "runtime",
                fixture: "mixed",
                frameLabel: frameLabel,
                returnFrameLabel: returnFrameLabel,
                debug: false,
                source: "arena_return"
            }
        }));
    }

    /**
     * 无人值守真实 E2E 的窄入口。C# 先绑定专用 cf7_agent_* 存档与本次 attempt，
     * 本函数再只复用正式 stage-select → panel_request → Host 白名单链路。
     * params 故意完全忽略：HTTP 不能选择 panel、difficulty、returnTo 或 initData。
     */
    public static function handleOpenArenaForAgent(params:Object):Boolean {
        cleanupStageSelectState();
        return requestOpenArenaPanel("冒险");
    }

    /**
     * 复位"web 选关打开中"状态。handleClose / handleReturnFrame 都要做这件事；
     * 角斗场重定向路径也需要走这步（否则切到 arena panel 期间，场景转换会以为
     * stage-select 还开着、拒绝其他转换，见 关卡系统_lsy_场景转换.as 中的检查）。
     */
    private static function cleanupStageSelectState():Void {
        if (_root.场景转换函数 == undefined) return;
        _root.场景转换函数.Web选关打开中 = false;
        if (_root.帧计时器 != undefined) {
            _root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;
        }
    }

    public static function handleJumpFrame(params:Object):Void {
        StageAdmissionBridge.panelClosed();
        var callId = params.callId;
        var frameLabel:String = String(params.frameLabel || params.targetFrameLabel || "");
        if (frameLabel == "") {
            sendResponse({
                task: "stage_select_response",
                callId: callId,
                success: false,
                error: "invalid_frame"
            });
            return;
        }

        frameLabel = resolveStageSelectFrameLabel(frameLabel);
        _root.Web选关当前帧值 = frameLabel;
        sendResponse({
            task: "stage_select_response",
            callId: callId,
            success: true,
            frameLabel: frameLabel
        });
    }

    public static function handleReturnFrame(params:Object):Void {
        var callId = params != undefined ? params.callId : undefined;
        var lifecycleReason:String =
            org.flashNight.arki.scene.StageRunSession.getSceneExitBlockReason();
        if (lifecycleReason != "") {
            sendResponse({
                task: "stage_select_response",
                callId: callId,
                success: false,
                error: "pending_stage_settlement"
            });
            return;
        }
        var frameLabel:String = "";
        if (params != undefined && params.returnFrameLabel != undefined) {
            frameLabel = String(params.returnFrameLabel);
        } else if (params != undefined && params.frameLabel != undefined) {
            frameLabel = String(params.frameLabel);
        } else if (_root.Web选关返回帧值 != undefined) {
            frameLabel = String(_root.Web选关返回帧值 || "");
        } else {
            frameLabel = String(_root.关卡地图帧值 || "基地门口");
        }
        // 返回目标是根场景身份，不能按关卡目录归一成选关页。
        frameLabel = resolveRootReturnFrameLabel(frameLabel);
        if (frameLabel == "") frameLabel = "基地门口";
        if (frameLabel == "地图-测试空间" && isChallengeMode()) {
            sendResponse({
                task: "stage_select_response",
                callId: callId,
                success: false,
                error: "challenge_mode_restricted"
            });
            return;
        }
        var skipTransition:Boolean = isAlreadyAtReturnFrame(frameLabel);

        if (!skipTransition && (_root.淡出动画 == undefined || _root.淡出动画.淡出跳转帧 == undefined)) {
            sendResponse({
                task: "stage_select_response",
                callId: callId,
                success: false,
                error: "stage_transition_unavailable"
            });
            return;
        }

        _root.关卡地图帧值 = frameLabel;
        _root.Web选关返回帧值 = frameLabel;
        _root.场景进入位置名 = "出生地";
        cleanupStageSelectState();

        sendResponse({
            task: "stage_select_response",
            callId: callId,
            success: true,
            closePanel: true,
            skippedTransition: skipTransition,
            returnFrameLabel: frameLabel
        });
        if (!skipTransition) {
            _root.淡出动画.淡出跳转帧(frameLabel);
        }
    }

    public static function handleClose(params:Object):Void {
        StageAdmissionBridge.panelClosed();
        cleanupStageSelectState();
    }

    public static function handleOpenWebStageSelect(params:Object):Boolean {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) {
            return false;
        }

        var source:String = (params != undefined && params.source != undefined)
            ? String(params.source)
            : "as2_stage_map_door";
        var rawFrame:String = (params != undefined && params.frameLabel != undefined)
            ? String(params.frameLabel)
            : "";
        if (rawFrame == "") rawFrame = String(_root.关卡地图帧值 || "基地门口");
        var returnFrame:String = (params != undefined && params.returnFrameLabel != undefined)
            ? String(params.returnFrameLabel)
            : "";
        if (returnFrame == "") returnFrame = String(_root.Web选关返回帧值 || _root.关卡地图帧值 || "基地门口");

        var stageFrame:String = resolveStageSelectFrameLabel(rawFrame);
        returnFrame = resolveRootReturnFrameLabel(returnFrame);
        if (stageFrame == "") stageFrame = "基地门口";
        if (returnFrame == "") returnFrame = "基地门口";

        _root.Web选关当前帧值 = stageFrame;
        _root.Web选关返回帧值 = returnFrame;
        _root.关卡地图帧值 = returnFrame;

        return _root.server.sendSocketMessage(_json.stringifySafe({
            task: "panel_request",
            panel: "stage-select",
            source: source,
            frameLabel: stageFrame,
            returnFrameLabel: returnFrame
        }));
    }

    private static function validateEnter(stageName:String, difficulty:String, entryKind:String):Object {
        if (stageName == "") return { success: false, error: "invalid_stage" };
        if (_root.StageInfoDict == undefined || _root.StageInfoDict[stageName] == undefined) {
            return { success: false, error: "invalid_stage" };
        }
        var stageInfo:Object = _root.StageInfoDict[stageName];
        if (stageInfo.Name !== stageName) return { success: false, error: "stage_config_failed" };
        var stageType:String = String(stageInfo.Type || "");
        if (entryKind == "map") {
            if (stageType != "外交地图") return { success: false, error: "unsupported_stage_type" };
            if (stageInfo.RootFadeTransitionFrame == undefined || stageInfo.RootFadeTransitionFrame == "") {
                return { success: false, error: "stage_config_failed" };
            }
            return { success: true, context: { stageInfo: stageInfo } };
        }
        if (entryKind == "task") {
            if (!isDifficultyStageType(stageType)) return { success: false, error: "unsupported_stage_type" };
            return { success: true, context: { stageInfo: stageInfo } };
        }
        if (entryKind != "difficulty") {
            return { success: false, error: "unsupported_entry_kind" };
        }
        if (!isDifficultyStageType(stageType)) {
            return { success: false, error: "unsupported_stage_type" };
        }
        if (!isValidDifficulty(difficulty)) {
            return { success: false, error: "invalid_difficulty" };
        }
        if (isChallengeMode() && difficulty != "地狱") {
            return { success: false, error: "challenge_requires_hell" };
        }
        if (typeof _root.配置关卡属性 != "function") {
            return { success: false, error: "stage_config_unavailable" };
        }

        var context:Object = {};
        context.配置关卡属性 = _root.配置关卡属性;
        context.配置关卡属性(stageName);
        if (context.关卡路径 == undefined || context.关卡路径 == "") {
            return { success: false, error: "stage_config_failed" };
        }
        return { success: true, context: context };
    }

    private static function performEnter(stageKey:String, context:Object,
            resolvedStageName:String, difficulty:String, entryKind:String,
            startToken:String, callId, grant:Object, onApplied:Function):Void {
        rememberEnterResponseContext(startToken, {
            callId:callId, onApplied:onApplied,
            stageName:stageKey,
            difficulty:difficulty,
            entryKind:entryKind
        });
        var settled:Boolean = false;
        var failOnce:Function = function(errorCode:String):Void {
            if (settled) return;
            settled = true;
            var uncertain:Boolean = false;
            try { restoreCommittedEnterTransitionState(startToken); }
            catch (restoreError) {
                uncertain = true;
                trace("[StageSelectPanelService] transition restore failed: "
                    + restoreError);
            }
            try {
                var manager:org.flashNight.arki.scene.StageManager =
                    org.flashNight.arki.scene.StageManager.instance;
                if (manager != null) manager.abortPreparedStage(startToken);
            } catch (managerAbortError) {
                uncertain = true;
                trace("[StageSelectPanelService] prepared stage abort failed: "
                    + managerAbortError);
            }
            try {
                org.flashNight.arki.scene.StageRunSession.cancelStageStart(startToken);
            } catch (reservationCancelError) {
                uncertain = true;
                trace("[StageSelectPanelService] reservation cancel failed: "
                    + reservationCancelError);
            }
            if (uncertain) errorCode = "stage_delivery_unknown";
            StageAdmissionBridge.outcome(grant, uncertain ? "unknown" : "failed");
            var stableContext:Object = null;
            try { stableContext = takeEnterResponseContextForFailure(startToken); }
            catch (contextError) {
                trace("[StageSelectPanelService] failure context take failed: "
                    + contextError);
            }
            if (stableContext != null) {
                try {
                    if (stableContext.onApplied != null) { stableContext.onApplied(false, errorCode); return; }
                    sendResponse({
                        task: "stage_select_response",
                        callId: stableContext.callId,
                        success: false,
                        error: errorCode
                    });
                } catch (failureResponseError) {
                    trace("[StageSelectPanelService] failure response failed: "
                        + failureResponseError);
                }
            } else {
                trace("[StageSelectPanelService] missing deferred response context");
            }
        };
        if (typeof _root.载入关卡数据 != "function"
                || resolvedStageName == ""
                || typeof _root.计算难度等级 != "function"
                || _root.淡出动画 == undefined
                || typeof _root.淡出动画.淡出跳转帧 != "function") {
            failOnce("stage_transition_unavailable");
            return;
        }
        var difficultyLevel:Number;
        try {
            difficultyLevel = _root.计算难度等级(difficulty);
        } catch (preflightError) {
            failOnce("stage_transition_unavailable");
            return;
        }
        var needsEntries:Boolean = context.限制词条 != undefined
            && context.限制词条 != null && context.限制词条.length > 0;
        var needsLimitLevel:Boolean = context.限制难度等级 != undefined
            && context.限制难度等级 != null;
        if ((needsEntries && (_root.限制系统 == undefined
                    || typeof _root.限制系统.openEntries != "function"))
                || (needsLimitLevel && (_root.限制系统 == undefined
                    || typeof _root.限制系统.addLimitLevel != "function"))) {
            failOnce("stage_transition_unavailable");
            return;
        }
        try {
            _root.载入关卡数据(context.关卡类型, context.关卡路径,
                StageAdmissionBridge.afterLoad(grant, function(data:Object):Void {
                    if (settled) return;
                    if (!org.flashNight.arki.scene.StageRunSession
                            .isStageStartReservationValid(startToken)) {
                        failOnce("stage_load_failed");
                        return;
                    }
                    var currentStageInfo:Object = _root.StageInfoDict[stageKey];
                    if (currentStageInfo == undefined
                            || String(currentStageInfo.Name || "") != resolvedStageName
                            || String(currentStageInfo.Type || "") != String(context.关卡类型 || "")
                            || String(currentStageInfo.url || "") != String(context.关卡路径 || "")) {
                        failOnce("stage_state_changed");
                        return;
                    }
                    if (!StageAdmissionBridge.seal(grant)) { failOnce("stage_state_changed"); return; }
                    try {
                        if (!promoteEnterResponseContext(startToken)) {
                            throw new Error("missing deferred response context");
                        }
                        _root.当前通关的关卡 = "";
                        _root.当前关卡难度 = difficulty;
                        _root.难度等级 = difficultyLevel;
                        _root.当前关卡名 = resolvedStageName;
                        _root.场景进入位置名 = "出生地";
                        _root.关卡类型 = context.关卡类型;

                        if (needsEntries) {
                            _root.限制系统.openEntries(context.限制词条);
                        }
                        if (needsLimitLevel) {
                            _root.限制系统.addLimitLevel(context.限制难度等级);
                        }
                        if (context.起点帧 != undefined && context.起点帧 != null
                                && context.起点帧 != "") {
                            _root.关卡地图帧值 = context.起点帧;
                        }

                        if (_root.soundEffectManager != undefined
                                && _root.soundEffectManager.stopBGMForTransition != undefined) {
                            _root.soundEffectManager.stopBGMForTransition();
                        }
                        if (_root.淡出动画.淡出跳转帧(context.淡出跳转帧) !== true) throw new Error("fade_rejected");
                    } catch (transitionError) {
                        trace("[StageSelectPanelService] stage transition failed: " + transitionError);
                        failOnce("stage_transition_failed");
                        return;
                    }
                    settled = true;
                    StageAdmissionBridge.outcome(grant, "committed");
                    try {
                        sendCommittedEnterResponse();
                    } catch (responseError) {
                        // 转场已经提交；transport 失败只能由 Host 后续对账，不能反向取消 token。
                        trace("[StageSelectPanelService] committed response failed: "
                            + responseError);
                    }
                }, failOnce),
                function():Void { failOnce("stage_load_failed"); }, startToken);
        } catch (loadStartError) {
            trace("[StageSelectPanelService] stage load failed: " + loadStartError);
            failOnce("stage_load_failed");
        }
    }

    private static function rememberEnterResponseContext(startToken:String,
            responseContext:Object):Void {
        if (_pendingEnterResponseContexts == null) _pendingEnterResponseContexts = {};
        _pendingEnterResponseContexts[startToken] = {
            startToken:startToken,
            responseContext:responseContext
        };
    }

    private static function takePendingEnterResponseContext(startToken:String):Object {
        if (_pendingEnterResponseContexts == null) return null;
        var record:Object = _pendingEnterResponseContexts[startToken];
        if (record == undefined || record == null
                || String(record.startToken || "") != startToken) return null;
        delete _pendingEnterResponseContexts[startToken];
        return record.responseContext;
    }

    private static function promoteEnterResponseContext(startToken:String):Boolean {
        if (_committedEnterResponseContext != null) return false;
        // 先完成可能抛错的快照，再消费 pending 信封；否则快照异常会丢掉 callId，
        // Host 只能等到 timeout。
        var transitionSnapshot:Object;
        try { transitionSnapshot = captureEnterTransitionState(); }
        catch (snapshotError) { return false; }
        var responseContext:Object = takePendingEnterResponseContext(startToken);
        if (responseContext == null) return false;
        _committedEnterResponseContext = {
            startToken:startToken,
            responseContext:responseContext,
            transitionSnapshot:transitionSnapshot
        };
        return true;
    }

    private static function takeEnterResponseContextForFailure(startToken:String):Object {
        var responseContext:Object = takePendingEnterResponseContext(startToken);
        if (responseContext != null) return responseContext;
        if (_committedEnterResponseContext == null
                || String(_committedEnterResponseContext.startToken || "") != startToken) {
            return null;
        }
        responseContext = _committedEnterResponseContext.responseContext;
        _committedEnterResponseContext = null;
        return responseContext;
    }

    private static function captureEnterTransitionState():Object {
        var restriction:Object = _root.限制系统;
        var entriesRef:Object = restriction != undefined && restriction != null
            ? restriction.entries : undefined;
        return {
            currentCompletedStage:_root.当前通关的关卡,
            currentDifficulty:_root.当前关卡难度,
            difficultyLevel:_root.难度等级,
            currentStageName:_root.当前关卡名,
            spawnName:_root.场景进入位置名,
            stageType:_root.关卡类型,
            hadMapFrame:_root.关卡地图帧值 != undefined,
            mapFrame:_root.关卡地图帧值,
            restriction:restriction,
            entriesRef:entriesRef,
            entriesSnapshot:cloneFlatObject(entriesRef),
            hadLimitLevel:restriction != undefined && restriction != null
                && restriction.limitLevel != undefined,
            limitLevel:restriction != undefined && restriction != null
                ? restriction.limitLevel : undefined
        };
    }

    private static function restoreCommittedEnterTransitionState(startToken:String):Void {
        var record:Object = _committedEnterResponseContext;
        if (record == null || String(record.startToken || "") != startToken
                || record.transitionSnapshot == null) return;
        var snapshot:Object = record.transitionSnapshot;
        _root.当前通关的关卡 = snapshot.currentCompletedStage;
        _root.当前关卡难度 = snapshot.currentDifficulty;
        _root.难度等级 = snapshot.difficultyLevel;
        _root.当前关卡名 = snapshot.currentStageName;
        _root.场景进入位置名 = snapshot.spawnName;
        _root.关卡类型 = snapshot.stageType;
        if (snapshot.hadMapFrame) _root.关卡地图帧值 = snapshot.mapFrame;
        else delete _root.关卡地图帧值;
        var restriction:Object = snapshot.restriction;
        if (restriction != undefined && restriction != null
                && _root.限制系统 === restriction) {
            if (snapshot.entriesRef != undefined && snapshot.entriesRef != null) {
                restriction.entries = snapshot.entriesRef;
                restoreFlatObject(snapshot.entriesRef, snapshot.entriesSnapshot);
            }
            if (snapshot.hadLimitLevel) restriction.limitLevel = snapshot.limitLevel;
            else delete restriction.limitLevel;
        }
        record.transitionSnapshot = null;
    }

    private static function cloneFlatObject(source:Object):Object {
        if (source == undefined || source == null) return null;
        var clone:Object = {};
        for (var key:String in source) clone[key] = source[key];
        return clone;
    }

    private static function restoreFlatObject(target:Object, snapshot:Object):Void {
        if (target == undefined || target == null) return;
        for (var key:String in target) delete target[key];
        if (snapshot == undefined || snapshot == null) return;
        for (var restoreKey:String in snapshot) target[restoreKey] = snapshot[restoreKey];
    }

    private static function sendCommittedEnterResponse():Void {
        var record:Object = _committedEnterResponseContext;
        _committedEnterResponseContext = null;
        if (record == null || record.responseContext == null) {
            throw new Error("missing committed response context");
        }
        var responseContext:Object = record.responseContext;
        if (responseContext.onApplied != null) { responseContext.onApplied(true, ""); return; }
        sendResponse({
            task: "stage_select_response",
            callId: responseContext.callId,
            success: true,
            closePanel: true,
            stageName: responseContext.stageName,
            difficulty: responseContext.difficulty,
            entryKind: responseContext.entryKind
        });
    }

    private static function performMapEnter(stageInfo:Object):Object {
        var lifecycleReason:String =
            org.flashNight.arki.scene.StageRunSession.getSceneExitBlockReason();
        if (lifecycleReason != "") {
            // 二次裁决只负责关闭 TOCTOU；外部仍保持既有统一错误契约。
            return { success: false, error: "pending_stage_settlement" };
        }
        if (_root.淡出动画 == undefined || _root.淡出动画.淡出跳转帧 == undefined) {
            return { success: false, error: "stage_transition_unavailable" };
        }
        var previous = _root.场景进入位置名;
        _root.场景进入位置名 = String(stageInfo.Address || "出生地");
        try {
            if (_root.淡出动画.淡出跳转帧(stageInfo.RootFadeTransitionFrame) !== true) throw new Error("fade_rejected");
        } catch (error) {
            _root.场景进入位置名 = previous;
            return {success:false, error:"stage_transition_failed"};
        }
        if (_root.soundEffectManager != null && typeof _root.soundEffectManager.stopBGMForTransition == "function") {
            try { _root.soundEffectManager.stopBGMForTransition(); } catch (audioError) {}
        }
        return {success:true};
    }

    private static function buildStageDetail(stageName:String, reason:String):Object {
        var taskInfo:Object = getTaskInfo(stageName);
        if (_root.StageInfoDict == undefined || _root.StageInfoDict[stageName] == undefined) {
            return {
                exists: false,
                stageType: "",
                detail: "",
                materialDetail: "",
                limitations: [],
                limitLevel: "",
                task: taskInfo.task,
                highestDifficulty: taskInfo.highestDifficulty,
                lockReason: reason
            };
        }

        var stageInfo:Object = _root.StageInfoDict[stageName];
        return {
            exists: true,
            stageType: String(stageInfo.Type || ""),
            detail: String(stageInfo.Description || ""),
            materialDetail: String(stageInfo.MaterialDetail || ""),
            limitations: parseLimitations(stageInfo),
            limitLevel: String(stageInfo.LimitLevel || ""),
            task: taskInfo.task,
            highestDifficulty: taskInfo.highestDifficulty,
            clearHistory: org.flashNight.arki.stageSelect.StageClearHistory.snapshot(stageName),
            lockReason: reason
        };
    }

    // 限制词条键名数组（原始 Limitation 键）。web 端用 LimitationDesc 自算 limitDetail，
    // 取代旧 _root.任务栏UI函数.打印限制词条明细 —— 移除 stage-select 对 任务栏UI.as 的依赖（其退役 keystone）。
    private static function parseLimitations(stageInfo:Object):Array {
        if (stageInfo == undefined || stageInfo.Limitation == undefined || stageInfo.Limitation == "") return [];
        if (typeof _root.配置数据为数组 != "function") return [];
        var entries:Array = _root.配置数据为数组(stageInfo.Limitation);
        return (entries == undefined || entries == null) ? [] : entries;
    }

    private static function getTaskInfo(stageName:String):Object {
        var info:Object = {
            task: false,
            highestDifficulty: "简单"
        };
        var tasks:Array = _root.tasks_to_do;
        if (tasks == undefined || tasks == null) return info;

        for (var i:Number = 0; i < tasks.length; i++) {
            var requirements:Object = tasks[i].requirements;
            if (requirements == undefined || requirements.stages == undefined) continue;
            for (var j in requirements.stages) {
                var taskStage:Object = requirements.stages[j];
                if (taskStage != undefined && stageName === taskStage.name) {
                    info.task = true;
                    if (difficultyRank(taskStage.difficulty) > difficultyRank(info.highestDifficulty)) {
                        info.highestDifficulty = taskStage.difficulty;
                    }
                }
            }
        }
        return info;
    }

    private static function isDifficultyStageType(stageType:String):Boolean {
        return stageType == "无限过图" || stageType == "初期关卡";
    }

    private static function isSupportedStageType(stageType:String):Boolean {
        return isDifficultyStageType(stageType) || stageType == "外交地图";
    }

    private static function resolveStageSelectFrameLabel(frameLabel:String):String {
        if (frameLabel == "") return "基地门口";
        if (frameLabel.indexOf("地图-") != 0) return frameLabel;
        if (_root.StageInfoDict == undefined) return frameLabel;

        for (var stageName in _root.StageInfoDict) {
            var stageInfo:Object = _root.StageInfoDict[stageName];
            if (stageInfo == undefined || stageInfo == null) continue;
            if (String(stageInfo.Type || "") != "外交地图") continue;
            if (String(stageInfo.RootFadeTransitionFrame || "") != frameLabel) continue;

            var folder:String = extractStageFolder(String(stageInfo.url || ""));
            if (folder != "") return folder;
        }
        return frameLabel;
    }

    private static function resolveRootReturnFrameLabel(frameLabel:String):String {
        // 大学等外交场景可共用车库选关页，但关闭后仍须回到各自真实场景。
        return frameLabel;
    }

    private static function isAlreadyAtReturnFrame(frameLabel:String):Boolean {
        if (frameLabel == "") return false;
        return org.flashNight.arki.map.MapHotspotResolver.isCurrentFrameName(frameLabel);
    }

    private static function extractStageFolder(url:String):String {
        if (url == "") return "";
        var parts:Array = url.split("/");
        for (var i:Number = 0; i < parts.length - 1; i++) {
            if (parts[i] == "stages" && parts[i + 1] != undefined && parts[i + 1] != "") {
                return String(parts[i + 1]);
            }
        }
        return "";
    }

    private static function isValidDifficulty(difficulty:String):Boolean {
        return difficulty == "简单" || difficulty == "冒险" || difficulty == "修罗" || difficulty == "地狱";
    }

    private static function difficultyRank(difficulty:String):Number {
        if (typeof _root.计算难度等级 == "function") return _root.计算难度等级(difficulty);
        if (difficulty == "冒险") return 2;
        if (difficulty == "修罗") return 3;
        if (difficulty == "地狱") return 4;
        return 1;
    }

    private static function isChallengeMode():Boolean {
        if (typeof _root.isChallengeMode != "function") return false;
        return _root.isChallengeMode() == true;
    }

    private static function normalizeStageNames(raw:Object):Array {
        var out:Array = [];
        if (raw instanceof Array) {
            for (var i:Number = 0; i < raw.length; i++) {
                var name:String = String(raw[i] || "");
                if (name != "") out.push(name);
            }
        }
        return out;
    }

    private static function sendResponse(resp:Object):Void {
        _root.server.sendSocketMessage(_json.stringifySafe(resp));
    }
}
