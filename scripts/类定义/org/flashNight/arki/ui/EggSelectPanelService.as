/**
 * U7 彩蛋地图选关（彩蛋地图电脑入口的旧 彩蛋地图关卡界面.swf 迁移）。
 * AS2 保留彩蛋进度门与进关权威；Web 面板只投影 snapshot 并回传目的地 id。
 */
class org.flashNight.arki.ui.EggSelectPanelService {
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;

    // 旧 SWF 待机帧（frame 40）的作者数据：目的地 id/关卡/固定难度/进关门槛。
    // hintEgg 是旧按钮 rollOver 的“尚未解锁”提示阈值（彩蛋 3/4/11），只作展示提示；
    // 真正的进关门以 requiresMain/requiresEgg 为准（与旧待机帧按钮一致）。
    private static var DESTINATIONS:Array = [
        {id:"forest_depth", name:"密林深处", stageName:"密林深处", difficulty:"简单",
            requiresEgg:0, requiresMain:0, hintEgg:3},
        {id:"machine_zone", name:"机器游荡区", stageName:"机器游荡区", difficulty:"简单",
            requiresEgg:4, requiresMain:67, hintEgg:4},
        {id:"forest_center", name:"密林中央", stageName:"密林中央", difficulty:"冒险",
            requiresEgg:11, requiresMain:0, hintEgg:11}
    ];

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["eggSelectSnapshot"] = function(params) { org.flashNight.arki.ui.EggSelectPanelService.handle("snapshot", params); };
        _root.gameCommands["eggSelectEnter"] = function(params) { org.flashNight.arki.ui.EggSelectPanelService.handle("enter", params); };
    }

    public static function openPanel():Boolean {
        if (typeof _root.server.sendSocketMessage != "function") return false;
        return _root.server.sendSocketMessage(org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "egg-stage-select", "world_egg_computer", [], [])) === true;
    }

    public static function handle(command:String, params:Object):Void {
        var response:Object = execute(command, params);
        response.task = "egg_select_response";
        response.callId = Number(params.callId);
        if (_json == undefined) _json = new LiteJSON();
        if (typeof _root.server.sendSocketMessage == "function") _root.server.sendSocketMessage(_json.stringifySafe(response));
    }

    public static function execute(command:String, params:Object):Object {
        if (command != "snapshot" && command != "enter") return fail(command, "unsupported_cmd");
        if (params == null || params.v !== 1) return fail(command, "unsupported_version");
        if (!hasOnly(params, command == "enter"
                ? ["v", "destinationId", "task", "action", "callId"]
                : ["v", "task", "action", "callId"])) return fail(command, "invalid_payload");
        if (command == "snapshot") return snapshot();
        return enter(params.destinationId);
    }

    private static function mainProgress():Number {
        var value:Number = Number(_root.主线任务进度);
        if (isNaN(value) || value < 0) return 0;
        return Math.floor(value);
    }
    private static function eggProgress():Number {
        var value:Number = Number(_root.task_chains_progress.彩蛋);
        if (isNaN(value) || value < 0) return 0;
        return Math.floor(value);
    }

    private static function unlocked(destination:Object):Boolean {
        return eggProgress() >= destination.requiresEgg && mainProgress() >= destination.requiresMain;
    }
    private static function lockReason(destination:Object):String {
        if (unlocked(destination)) return "";
        var reason:String = "";
        if (destination.requiresEgg > 0 && eggProgress() < destination.requiresEgg)
            reason = "彩蛋进度达到 " + destination.requiresEgg;
        if (destination.requiresMain > 0 && mainProgress() < destination.requiresMain) {
            if (reason != "") reason += "，";
            reason += "主线任务进度达到 " + destination.requiresMain;
        }
        return reason + " 解锁";
    }

    private static function snapshot():Object {
        var egg:Number = eggProgress();
        var destinations:Array = [];
        for (var i:Number = 0; i < DESTINATIONS.length; i++) {
            var destination:Object = DESTINATIONS[i];
            destinations.push({id:destination.id, name:destination.name,
                stageName:destination.stageName, difficulty:destination.difficulty,
                unlocked:unlocked(destination), hintLocked:egg < destination.hintEgg,
                lockReason:lockReason(destination)});
        }
        return {v:1, operation:"snapshot", success:true,
            progress:{main:mainProgress(), egg:egg}, destinations:destinations};
    }

    private static function enter(destinationId):Object {
        if (typeof destinationId != "string") return fail("enter", "invalid_payload");
        var destination:Object = null;
        for (var i:Number = 0; i < DESTINATIONS.length; i++) {
            if (DESTINATIONS[i].id == destinationId) { destination = DESTINATIONS[i]; break; }
        }
        if (destination == null) return fail("enter", "unknown_destination");
        if (!unlocked(destination)) return fail("enter", "locked");
        if (_root.StageInfoDict == undefined || _root.StageInfoDict[destination.stageName] == undefined)
            return fail("enter", "stage_config_unavailable");
        if (org.flashNight.arki.scene.StageRunSession.getStageStartBlockReason() != "")
            return fail("enter", "pending_stage_settlement");
        if (typeof _root.配置关卡属性 != "function" || typeof _root.选关界面进入关卡 != "function")
            return fail("enter", "stage_config_unavailable");
        // 旧 SWF 确认框的进关链：holder 上先 配置关卡属性 再 选关界面进入关卡，
        // 后者内建 StageRunSession.reserveStageStart 的奖励未领拒绝。
        var holder:Object = {};
        holder.配置关卡属性 = _root.配置关卡属性;
        holder.配置关卡属性(destination.stageName);
        if (holder.关卡路径 == undefined || holder.关卡路径 == "") return fail("enter", "stage_config_failed");
        holder.选关界面进入关卡 = _root.选关界面进入关卡;
        if (holder.选关界面进入关卡(destination.difficulty) !== true) return fail("enter", "enter_refused");
        return {v:1, operation:"enter", success:true, closePanel:true,
            destinationId:destination.id, stageName:destination.stageName, difficulty:destination.difficulty};
    }

    private static function hasOnly(value:Object, allowed:Array):Boolean {
        for (var key:String in value) {
            var found:Boolean = false;
            for (var i:Number = 0; i < allowed.length; i++) if (allowed[i] == key) found = true;
            if (!found) return false;
        }
        return true;
    }
    private static function fail(operation:String, error:String):Object {
        return {v:1, success:false, operation:operation, error:error};
    }
}
