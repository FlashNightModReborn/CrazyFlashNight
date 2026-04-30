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

        _inited = true;
    }

    public static function handleSnapshot(params:Object):Void {
        var callId = params.callId;
        var names:Array = normalizeStageNames(params.stageNames);
        var unlocked:Object = {};
        var details:Object = {};
        var i:Number;

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
                currentFrameLabel: String(_root.关卡地图帧值 || "")
            }
        });
    }

    public static function handleEnter(params:Object):Void {
        var callId = params.callId;
        var stageName:String = String(params.stageName || "");
        var difficulty:String = String(params.difficulty || "");
        var validation:Object = validateEnter(stageName, difficulty);

        if (!validation.success) {
            validation.task = "stage_select_response";
            validation.callId = callId;
            sendResponse(validation);
            return;
        }

        performEnter(validation.context, difficulty);

        sendResponse({
            task: "stage_select_response",
            callId: callId,
            success: true,
            closePanel: true,
            stageName: stageName,
            difficulty: difficulty
        });
    }

    private static function validateEnter(stageName:String, difficulty:String):Object {
        if (stageName == "") return { success: false, error: "invalid_stage" };
        if (_root.StageInfoDict == undefined || _root.StageInfoDict[stageName] == undefined) {
            return { success: false, error: "invalid_stage" };
        }
        if (!isSupportedStageType(_root.StageInfoDict[stageName].Type)) {
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

    private static function isSupportedStageType(stageType:String):Boolean {
        return stageType == "无限过图" || stageType == "初期关卡";
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
