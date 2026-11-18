import org.flashNight.arki.stageSelect.StageAdmissionBridge;
import org.flashNight.arki.stageSelect.StageSelectPanelService;

/**
 * U7 彩蛋地图选关（彩蛋地图电脑入口的旧 彩蛋地图关卡界面.swf 迁移）。
 * 启动器裁决彩蛋入口；Flash 采样并提交场景，Web 发送目的地。
 */
class org.flashNight.arki.ui.EggSelectPanelService {
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;

    // 旧 SWF 待机帧（frame 40）的作者数据：目的地 id/关卡/固定难度/进关门槛。
    // hintEgg 是旧按钮 rollOver 的“尚未解锁”提示阈值（彩蛋 3/4/11），只作展示提示；
    // 进关门由 data/stages/entry-policies.xml 提供。
    private static var DESTINATIONS:Array = [
        {id:"forest_depth", name:"密林深处", stageName:"密林深处", difficulty:"简单",
            hintEgg:3},
        {id:"machine_zone", name:"机器游荡区", stageName:"机器游荡区", difficulty:"简单",
            hintEgg:4},
        {id:"forest_center", name:"密林中央", stageName:"密林中央", difficulty:"冒险",
            hintEgg:11}
    ];

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["eggSelectSnapshot"] = function(params) { org.flashNight.arki.ui.EggSelectPanelService.handle("snapshot", params); };
        _root.gameCommands["eggSelectEnter"] = function(params) { org.flashNight.arki.ui.EggSelectPanelService.handle("enter", params); };
        _root.gameCommands["openEggStageSelectForAgent"] = function():Boolean { return _root._agentHarnessActive === true && org.flashNight.arki.ui.EggSelectPanelService.openPanel(); };
    }

    public static function openPanel():Boolean {
        if (typeof _root.server.sendSocketMessage != "function") return false;
        return _root.server.sendSocketMessage(org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "egg-stage-select", "world_egg_computer", [], [])) === true;
    }

    public static function handle(command:String, params:Object):Void {
        execute(command, params, function(response:Object):Void {
            response.task = "egg_select_response";
            response.callId = Number(params.callId);
            if (_json == undefined) _json = new LiteJSON();
            if (typeof _root.server.sendSocketMessage == "function") _root.server.sendSocketMessage(_json.stringifySafe(response));
        });
    }

    public static function execute(command:String, params:Object, callback:Function):Object {
        var invalid:String = "";
        if (command != "snapshot" && command != "enter") invalid = "unsupported_cmd";
        else if (params == null || params.v !== 1) invalid = "unsupported_version";
        else if (!hasOnly(params, command == "enter" ? ["v","destinationId","task","action","callId"]
                : ["v","task","action","callId"])) invalid = "invalid_payload";
        var names:Array = [];
        var target:Object;
        for (var i:Number = 0; i < DESTINATIONS.length; i++) {
            var item:Object = DESTINATIONS[i];
            names.push(item.stageName || item.name);
            if (item.id === params.destinationId) target = item;
        }
        if (invalid == "" && command == "enter") {
            if (typeof params.destinationId != "string") invalid = "invalid_payload";
            else if (target == null) invalid = "unknown_destination";
            else if (target.stageName == "") invalid = "not_enterable";
        }
        if (invalid != "" || callback == null) {
            var rejected:Object = fail(command, invalid || "admission_required");
            if (callback != null) callback(rejected);
            return rejected;
        }
        var owner:String = "egg."+params.callId;
        if (command == "snapshot") {
            StageAdmissionBridge.request(names,"egg","",StageAdmissionBridge.nextId(),owner,false,null,
                function(result:Object, why:String):Void {
                    callback(result == null ? fail(command,why) : snapshot(result.decisions));
                });
        } else {
            StageSelectPanelService.enterFromWorld(target.stageName,target.difficulty,"egg",owner,
                function(ok:Boolean, why:String):Void {
                    if (!ok) { callback(fail(command,why)); return; }
                    callback({v:1,operation:"enter",success:true,closePanel:true,destinationId:target.id,
                        stageName:target.stageName,difficulty:target.difficulty});
                });
        }
        return null;
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

    public static function snapshot(decisions:Object):Object {
        var egg:Number = eggProgress();
        var destinations:Array = [];
        for (var i:Number = 0; i < DESTINATIONS.length; i++) {
            var destination:Object = DESTINATIONS[i];
            destinations.push({id:destination.id, name:destination.name,
                stageName:destination.stageName, difficulty:destination.difficulty,
                unlocked:decisions[destination.stageName].unlocked === true, hintLocked:egg < destination.hintEgg,
                lockReason:String(decisions[destination.stageName].reason || "")});
        }
        return {v:1, operation:"snapshot", success:true,
            progress:{main:mainProgress(), egg:egg}, destinations:destinations};
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
