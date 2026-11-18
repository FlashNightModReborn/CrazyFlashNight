import org.flashNight.arki.stageSelect.StageAdmissionBridge;
import org.flashNight.arki.stageSelect.StageSelectPanelService;

/**
 * U7 地铁线路选关（隧道据点 DefineButton2_64 入口的旧 地铁线路UI.swf 迁移）。
 * 启动器裁决地铁入口；Flash 保留站点画面与实际转场。
 */
class org.flashNight.arki.ui.SubwaySelectPanelService {
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;

    // 旧 SWF 的作者数据表：id/显示名/说明/关卡/难度/可否进入。enterable=false 的
    // defend_stationC 在旧界面点击只 trace，不产生进关。
    private static var ENTRIES:Array = [
        {id:"clean_stationA", name:"清理总备处", description:"清理总备处站，尝试搜寻神秘士兵的据点。",
            stageName:"总备处站清理", difficulty:"简单", enterable:true},
        {id:"raid_stationB", name:"突袭新市场", description:"进入密林深处副本",
            stageName:"密林深处", difficulty:"简单", enterable:true},
        {id:"defend_stationC", name:"自由广场防守", description:"",
            stageName:"", difficulty:"", enterable:false},
        {id:"explore_stationD", name:"环线东北站探索", description:"探索环线东北站",
            stageName:"环线东北站", difficulty:"简单", enterable:true}
    ];
    private static var STATIONS:Array = ["总备处站", "新市场站", "自由广场站", "环线东北站"];

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["subwaySelectSnapshot"] = function(params) { org.flashNight.arki.ui.SubwaySelectPanelService.handle("snapshot", params); };
        _root.gameCommands["subwaySelectEnter"] = function(params) { org.flashNight.arki.ui.SubwaySelectPanelService.handle("enter", params); };
        _root.gameCommands["openSubwayForAgent"] = function():Boolean { return _root._agentHarnessActive === true && org.flashNight.arki.ui.SubwaySelectPanelService.openPanel(); };
    }

    public static function openPanel():Boolean {
        if (typeof _root.server.sendSocketMessage != "function") return false;
        return _root.server.sendSocketMessage(org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "subway", "world_subway", [], [])) === true;
    }

    public static function handle(command:String, params:Object):Void {
        execute(command, params, function(response:Object):Void {
            response.task = "subway_select_response";
            response.callId = Number(params.callId);
            if (_json == undefined) _json = new LiteJSON();
            if (typeof _root.server.sendSocketMessage == "function") _root.server.sendSocketMessage(_json.stringifySafe(response));
        });
    }

    public static function execute(command:String, params:Object, callback:Function):Object {
        var invalid:String = "";
        if (command != "snapshot" && command != "enter") invalid = "unsupported_cmd";
        else if (params == null || params.v !== 1) invalid = "unsupported_version";
        else if (!hasOnly(params, command == "enter" ? ["v","entryId","task","action","callId"]
                : ["v","task","action","callId"])) invalid = "invalid_payload";
        var names:Array = [];
        var target:Object;
        for (var i:Number = 0; i < ENTRIES.length; i++) {
            var item:Object = ENTRIES[i];
            names.push(item.stageName || item.name);
            if (item.id === params.entryId) target = item;
        }
        if (invalid == "" && command == "enter") {
            if (typeof params.entryId != "string") invalid = "invalid_payload";
            else if (target == null) invalid = "unknown_entry";
            else if (target.stageName == "") invalid = "not_enterable";
        }
        if (invalid != "" || callback == null) {
            var rejected:Object = fail(command, invalid || "admission_required");
            if (callback != null) callback(rejected);
            return rejected;
        }
        var owner:String = "subway."+params.callId;
        if (command == "snapshot") {
            StageAdmissionBridge.request(names,"subway","",StageAdmissionBridge.nextId(),owner,false,null,
                function(result:Object, why:String):Void {
                    callback(result == null ? fail(command,why) : snapshot(result.decisions));
                });
        } else {
            StageSelectPanelService.enterFromWorld(target.stageName,target.difficulty,"subway",owner,
                function(ok:Boolean, why:String):Void {
                    if (!ok) { callback(fail(command,why)); return; }
                    callback({v:1,operation:"enter",success:true,closePanel:true,entryId:target.id,
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

    // 旧 SWF 逐条目的 showCondition / getFrame 帧语义：visible 决定条目是否出现，
    // highlighted 对应旧按钮第 2 帧（达成态）。
    private static function highlighted(id:String):Boolean {
        if (id == "clean_stationA") return mainProgress() >= 30;
        if (id == "raid_stationB") return mainProgress() >= 67;
        if (id == "defend_stationC") return _root.任务进度.自由广场已完成 == true;
        return mainProgress() >= 50;
    }

    // 旧线路图四站跳帧：新市场站未达 彩蛋>=4 且 主线>=67 时停在锁定帧。
    private static function stationFrame(name:String):Number {
        if (name == "总备处站") return 4;
        if (name == "新市场站") return (eggProgress() >= 4 && mainProgress() >= 67) ? 3 : 1;
        if (name == "自由广场站") return 2;
        return 3;
    }

    public static function snapshot(decisions:Object):Object {
        var stations:Array = [];
        for (var i:Number = 0; i < STATIONS.length; i++) {
            stations.push({id:STATIONS[i], name:STATIONS[i], frame:stationFrame(STATIONS[i])});
        }
        var entries:Array = [];
        for (var j:Number = 0; j < ENTRIES.length; j++) {
            var entry:Object = ENTRIES[j];
            var decision:Object = decisions[entry.stageName || entry.name];
            if (decision.nativeUnlocked !== true) continue;
            entries.push({id:entry.id, name:entry.name, description:entry.description,
                stageName:entry.stageName, difficulty:entry.difficulty,
                enterable:decision.unlocked === true, highlighted:highlighted(entry.id)});
        }
        return {v:1, operation:"snapshot", success:true,
            progress:{main:mainProgress(), egg:eggProgress()},
            stations:stations, entries:entries};
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
