/**
 * U7 地铁线路选关（隧道据点 DefineButton2_64 入口的旧 地铁线路UI.swf 迁移）。
 * AS2 保留站点/目的地/门槛与进关权威；Web 面板只投影 snapshot 并回传目的地 id。
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
    }

    public static function openPanel():Boolean {
        if (typeof _root.server.sendSocketMessage != "function") return false;
        return _root.server.sendSocketMessage(org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "subway", "world_subway", [], [])) === true;
    }

    public static function handle(command:String, params:Object):Void {
        var response:Object = execute(command, params);
        response.task = "subway_select_response";
        response.callId = Number(params.callId);
        if (_json == undefined) _json = new LiteJSON();
        if (typeof _root.server.sendSocketMessage == "function") _root.server.sendSocketMessage(_json.stringifySafe(response));
    }

    public static function execute(command:String, params:Object):Object {
        if (command != "snapshot" && command != "enter") return fail(command, "unsupported_cmd");
        if (params == null || params.v !== 1) return fail(command, "unsupported_version");
        if (!hasOnly(params, command == "enter"
                ? ["v", "entryId", "task", "action", "callId"]
                : ["v", "task", "action", "callId"])) return fail(command, "invalid_payload");
        if (command == "snapshot") return snapshot();
        return enter(params.entryId);
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
    private static function entryState(id:String):Object {
        var main:Number = mainProgress();
        var egg:Number = eggProgress();
        if (id == "clean_stationA") return {visible:main >= 45, highlighted:main >= 30};
        if (id == "raid_stationB") return {visible:egg >= 4, highlighted:main >= 67};
        if (id == "defend_stationC") return {visible:main >= 20,
            highlighted:(_root.任务进度 && _root.任务进度.自由广场已完成) ? true : false};
        if (id == "explore_stationD") return {visible:true, highlighted:main >= 50};
        return null;
    }

    // 旧线路图四站跳帧：新市场站未达 彩蛋>=4 且 主线>=67 时停在锁定帧。
    private static function stationFrame(name:String):Number {
        if (name == "总备处站") return 4;
        if (name == "新市场站") return (eggProgress() >= 4 && mainProgress() >= 67) ? 3 : 1;
        if (name == "自由广场站") return 2;
        return 3;
    }

    private static function snapshot():Object {
        var stations:Array = [];
        for (var i:Number = 0; i < STATIONS.length; i++) {
            stations.push({id:STATIONS[i], name:STATIONS[i], frame:stationFrame(STATIONS[i])});
        }
        var entries:Array = [];
        for (var j:Number = 0; j < ENTRIES.length; j++) {
            var entry:Object = ENTRIES[j];
            var state:Object = entryState(entry.id);
            if (!state.visible) continue;
            entries.push({id:entry.id, name:entry.name, description:entry.description,
                stageName:entry.stageName, difficulty:entry.difficulty,
                enterable:entry.enterable, highlighted:state.highlighted});
        }
        return {v:1, operation:"snapshot", success:true,
            progress:{main:mainProgress(), egg:eggProgress()},
            stations:stations, entries:entries};
    }

    private static function enter(entryId):Object {
        if (typeof entryId != "string") return fail("enter", "invalid_payload");
        var entry:Object = null;
        for (var i:Number = 0; i < ENTRIES.length; i++) {
            if (ENTRIES[i].id == entryId) { entry = ENTRIES[i]; break; }
        }
        if (entry == null) return fail("enter", "unknown_entry");
        var state:Object = entryState(entry.id);
        if (state == null || !state.visible) return fail("enter", "locked");
        if (!entry.enterable) return fail("enter", "not_enterable");
        if (_root.StageInfoDict == undefined || _root.StageInfoDict[entry.stageName] == undefined)
            return fail("enter", "stage_config_unavailable");
        if (org.flashNight.arki.scene.StageRunSession.getStageStartBlockReason() != "")
            return fail("enter", "pending_stage_settlement");
        if (typeof _root.配置关卡属性 != "function" || typeof _root.选关界面进入关卡 != "function")
            return fail("enter", "stage_config_unavailable");
        // 旧 SWF 的进关链：holder 上先 配置关卡属性 再 选关界面进入关卡，
        // 后者内建 StageRunSession.reserveStageStart 的奖励未领拒绝。
        var holder:Object = {};
        holder.配置关卡属性 = _root.配置关卡属性;
        holder.配置关卡属性(entry.stageName);
        if (holder.关卡路径 == undefined || holder.关卡路径 == "") return fail("enter", "stage_config_failed");
        holder.选关界面进入关卡 = _root.选关界面进入关卡;
        if (holder.选关界面进入关卡(entry.difficulty) !== true) return fail("enter", "enter_refused");
        return {v:1, operation:"enter", success:true, closePanel:true,
            entryId:entry.id, stageName:entry.stageName, difficulty:entry.difficulty};
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
