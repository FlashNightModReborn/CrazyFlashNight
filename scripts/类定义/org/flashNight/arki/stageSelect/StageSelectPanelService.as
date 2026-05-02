/**
 * 文件：org/flashNight/arki/stageSelect/StageSelectPanelService.as
 * 说明：WebView 选关面板测试入口的真实进关桥。
 */
class org.flashNight.arki.stageSelect.StageSelectPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;

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
        var names:Array = normalizeStageNames(params.stageNames);
        var unlocked:Object = {};
        var details:Object = {};
        var i:Number;

        if (requestedFrameLabel != "") _root.Web选关当前帧值 = requestedFrameLabel;
        if (requestedReturnFrameLabel != "") _root.Web选关返回帧值 = requestedReturnFrameLabel;

        for (i = 0; i < names.length; i++) {
            unlocked[names[i]] = canEnterStage(names[i]);
            details[names[i]] = buildStageDetail(names[i]);
        }

        sendResponse({
            task: "stage_select_response",
            callId: callId,
            success: true,
            snapshot: {
                unlockedStages: unlocked,
                stageDetails: details,
                isChallengeMode: isChallengeMode(),
                currentFrameLabel: resolveStageSelectFrameLabel(String(_root.Web选关当前帧值 || _root.关卡地图帧值 || "")),
                returnFrameLabel: resolveRootReturnFrameLabel(String(_root.Web选关返回帧值 || _root.关卡地图帧值 || ""))
            }
        });
    }

    public static function handleEnter(params:Object):Void {
        var callId = params.callId;
        var stageName:String = String(params.stageName || "");
        var difficulty:String = String(params.difficulty || "");
        var entryKind:String = String(params.entryKind || "difficulty");
        if (entryKind == "") entryKind = "difficulty";
        var validation:Object = validateEnter(stageName, difficulty, entryKind);

        if (!validation.success) {
            validation.task = "stage_select_response";
            validation.callId = callId;
            sendResponse(validation);
            return;
        }

        var actionResult:Object;
        if (entryKind == "map") {
            actionResult = performMapEnter(validation.context.stageInfo);
        } else if (entryKind == "task") {
            actionResult = performTaskOpen(stageName);
        } else {
            performEnter(validation.context, difficulty);
            actionResult = { success: true };
        }

        if (!actionResult.success) {
            actionResult.task = "stage_select_response";
            actionResult.callId = callId;
            sendResponse(actionResult);
            return;
        }

        sendResponse({
            task: "stage_select_response",
            callId: callId,
            success: true,
            closePanel: true,
            stageName: stageName,
            difficulty: difficulty,
            entryKind: entryKind
        });
    }

    public static function handleJumpFrame(params:Object):Void {
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
        // skipTransition 判定要在 frameLabel 转 url folder 之前做:
        // resolveRootReturnFrameLabel 会把外交地图 "地图-XXX" 替换成 stage url folder (英文),
        // 而 MapHotspotResolver.isCurrentFrameName 是按 NAVIGATE_TARGETS 中文 frame name 匹配的——
        // 用 url folder 永远查不到, 会让"已在外交地图入口时按返回"误走重复淡出.
        var rawReturnFrameLabel:String = frameLabel;
        frameLabel = resolveRootReturnFrameLabel(frameLabel);
        if (frameLabel == "") frameLabel = "基地门口";
        var skipTransition:Boolean = isAlreadyAtReturnFrame(rawReturnFrameLabel != "" ? rawReturnFrameLabel : frameLabel);

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
        if (_root.场景转换函数 != undefined) {
            _root.场景转换函数.Web选关打开中 = false;
            if (_root.帧计时器 != undefined) {
                _root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;
            }
        }

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
        if (_root.场景转换函数 != undefined) {
            _root.场景转换函数.Web选关打开中 = false;
            if (_root.帧计时器 != undefined) {
                _root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;
            }
        }
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

        return _root.server.sendSocketMessage(_json.stringify({
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
        var stageType:String = String(stageInfo.Type || "");
        if (entryKind == "map") {
            if (stageType != "外交地图") return { success: false, error: "unsupported_stage_type" };
            if (!canEnterStage(stageName)) return { success: false, error: "locked" };
            if (stageInfo.RootFadeTransitionFrame == undefined || stageInfo.RootFadeTransitionFrame == "") {
                return { success: false, error: "stage_config_failed" };
            }
            return { success: true, context: { stageInfo: stageInfo } };
        }
        if (entryKind == "task") {
            if (!isDifficultyStageType(stageType)) return { success: false, error: "unsupported_stage_type" };
            if (!canEnterStage(stageName)) return { success: false, error: "locked" };
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
        if (!canEnterStage(stageName)) {
            return { success: false, error: "locked" };
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

    private static function performEnter(context:Object, difficulty:String):Void {
        _root.载入关卡数据(context.关卡类型, context.关卡路径);
        _root.当前通关的关卡 = "";
        _root.当前关卡难度 = difficulty;
        _root.难度等级 = _root.计算难度等级(_root.当前关卡难度);
        _root.当前关卡名 = context.当前关卡名;
        _root.场景进入位置名 = "出生地";
        _root.关卡类型 = context.关卡类型;

        if (context.限制词条 != undefined && context.限制词条 != null && context.限制词条.length > 0) {
            _root.限制系统.openEntries(context.限制词条);
        }
        if (context.限制难度等级 != undefined && context.限制难度等级 != null) {
            _root.限制系统.addLimitLevel(context.限制难度等级);
        }
        if (context.起点帧 != undefined && context.起点帧 != null && context.起点帧 != "") {
            _root.关卡地图帧值 = context.起点帧;
        }

        if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
            _root.soundEffectManager.stopBGMForTransition();
        }
        _root.淡出动画.淡出跳转帧(context.淡出跳转帧);
    }

    private static function performMapEnter(stageInfo:Object):Object {
        if (_root.淡出动画 == undefined || _root.淡出动画.淡出跳转帧 == undefined) {
            return { success: false, error: "stage_transition_unavailable" };
        }
        _root.场景进入位置名 = String(stageInfo.Address || "出生地");
        if (_root.soundEffectManager != undefined && _root.soundEffectManager.stopBGMForTransition != undefined) {
            _root.soundEffectManager.stopBGMForTransition();
        }
        _root.淡出动画.淡出跳转帧(stageInfo.RootFadeTransitionFrame);
        return { success: true };
    }

    private static function performTaskOpen(stageName:String):Object {
        var panel:Object = _root.委托任务界面;
        if (panel == undefined || panel == null) {
            return { success: false, error: "task_ui_unavailable" };
        }
        if (typeof _root.getTaskData != "function") {
            return { success: false, error: "task_data_unavailable" };
        }
        var taskData:Object = _root.getTaskData(stageName);
        if (taskData == undefined || taskData == null) {
            return { success: false, error: "task_data_unavailable" };
        }
        if (typeof panel.显示任务明细 != "function") {
            return { success: false, error: "task_ui_unavailable" };
        }
        if (typeof panel.配置关卡属性 != "function") {
            if (typeof _root.配置关卡属性 != "function") {
                return { success: false, error: "stage_config_unavailable" };
            }
            panel.配置关卡属性 = _root.配置关卡属性;
        }

        panel.NPC任务_任务_起始帧 = null;
        panel.taskData = taskData;
        panel.NPC任务_任务_契约金 = taskData.deposit;
        panel.NPC任务_任务_等级限制 = taskData.restricted_level;
        panel.NPC任务_任务_K点 = taskData.Kdeposit;
        if (typeof _root.SetDialogue == "function") {
            _root.SetDialogue(taskData.get_conversation);
        }
        panel.配置关卡属性(stageName);
        panel.显示任务明细(taskData);
        panel._visible = true;
        return { success: true };
    }

    private static function canEnterStage(stageName:String):Boolean {
        if (stageName == "") return false;
        if (_root.StageInfoDict == undefined || _root.StageInfoDict[stageName] == undefined) return false;
        if (!isSupportedStageType(_root.StageInfoDict[stageName].Type)) return false;
        if (typeof _root.isStageUnlocked != "function") return false;
        return _root.isStageUnlocked(stageName) == true;
    }

    private static function buildStageDetail(stageName:String):Object {
        var taskInfo:Object = getTaskInfo(stageName);
        if (_root.StageInfoDict == undefined || _root.StageInfoDict[stageName] == undefined) {
            return {
                exists: false,
                stageType: "",
                detail: "",
                materialDetail: "",
                limitDetail: "",
                limitLevel: "",
                task: taskInfo.task,
                highestDifficulty: taskInfo.highestDifficulty
            };
        }

        var stageInfo:Object = _root.StageInfoDict[stageName];
        return {
            exists: true,
            stageType: String(stageInfo.Type || ""),
            detail: String(stageInfo.Description || ""),
            materialDetail: String(stageInfo.MaterialDetail || ""),
            limitDetail: buildLimitDetail(stageInfo),
            limitLevel: String(stageInfo.LimitLevel || ""),
            task: taskInfo.task,
            highestDifficulty: taskInfo.highestDifficulty
        };
    }

    private static function buildLimitDetail(stageInfo:Object):String {
        if (stageInfo == undefined || stageInfo.Limitation == undefined || stageInfo.Limitation == "") return "";
        if (typeof _root.配置数据为数组 != "function") return "";
        if (_root.任务栏UI函数 == undefined || typeof _root.任务栏UI函数.打印限制词条明细 != "function") return "";

        var entries:Array = _root.配置数据为数组(stageInfo.Limitation);
        if (entries == undefined || entries == null || entries.length <= 0) return "";
        return String(_root.任务栏UI函数.打印限制词条明细(entries, stageInfo.LimitLevel));
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
        if (frameLabel == "") return "";
        if (frameLabel.indexOf("地图-") == 0) return resolveStageSelectFrameLabel(frameLabel);
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
        _root.server.sendSocketMessage(_json.stringify(resp));
    }
}
