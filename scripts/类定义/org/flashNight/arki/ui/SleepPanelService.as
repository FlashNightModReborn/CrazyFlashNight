import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.neur.Event.EventBus;

/** 床铺授权的睡眠会话。Web 只编辑目标分钟，AS2 一次性提交运行态时刻。 */
class org.flashNight.arki.ui.SleepPanelService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _active:Object;
    private static var _records:Object = {};
    private static var _order:Array = [];
    private static var _json:LiteJSON;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["sleepSnapshot"] = function(params) { org.flashNight.arki.ui.SleepPanelService.handle("snapshot", params); };
        _root.gameCommands["sleepCommit"] = function(params) { org.flashNight.arki.ui.SleepPanelService.handle("commit", params); };
        _root.gameCommands["sleepQuery"] = function(params) { org.flashNight.arki.ui.SleepPanelService.handle("query", params); };
        EventBus.getInstance().subscribe("SceneChanged", onSceneChanged, org.flashNight.arki.ui.SleepPanelService);
    }

    public static function openPanel():Boolean {
        if (typeof _root.server.sendSocketMessage != "function" || _root.gameworld == undefined) return false;
        retireActive();
        var weather:WeatherSystem = WeatherSystem.getInstance();
        var time:Number = weather.getCurrentTime();
        if (isNaN(time) || time < 0 || time >= 24) return false;
        var owner:Object = {};
        _root.gameworld.__sleepPanelOwner = owner;
        _active = {
            token:"sleep." + getTimer() + "." + (++_sequence), phase:"editing",
            currentMinutes:Math.floor(time * 60) % 1440, targetMinutes:Math.floor(time * 60) % 1440,
            owner:owner, slot:String(_root.savePath), scene:String(_root.关卡标志),
            cycleEnabled:weather.enableDayNightCycle === true, cyclePaused:weather.pauseDayNightCycle === true,
            reason:""
        };
        _records[_active.token] = _active;
        _order.push(_active.token);
        // 仅保留本次进程的最近操作收据；不引入存档字段。
        if (_order.length > 32) delete _records[_order.shift()];
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "sleep", "world_sleep", [], [{name:"token", value:_active.token}]
        );
        if (_root.server.sendSocketMessage(payload) === false) { retireActive(); return false; }
        return true;
    }

    public static function handle(command:String, params:Object):Void {
        var response:Object = execute(command, params);
        response.task = "sleep_response";
        response.callId = Number(params.callId);
        if (_json == undefined) _json = new LiteJSON();
        if (typeof _root.server.sendSocketMessage == "function") _root.server.sendSocketMessage(_json.stringifySafe(response));
    }

    public static function execute(command:String, params:Object):Object {
        var token:String = typeof params.token == "string" ? params.token : "";
        if (command != "snapshot" && command != "commit" && command != "query") return fail(command, token, "unsupported_cmd");
        if (params.v !== 1) return fail(command, token, "unsupported_version");
        if (!hasOnly(params, command == "commit"
                ? ["v", "token", "targetMinutes", "task", "action", "callId"]
                : ["v", "token", "task", "action", "callId"]) || token == "") return fail(command, token, "invalid_payload");
        var record:Object = _records[token];
        if (record == undefined) return fail(command, token, "stale_token");
        if (command == "commit" && !minute(params.targetMinutes)) return fail(command, token, "invalid_payload");
        if (record.phase == "editing" && !sameContext(record)) { record.phase = "expired"; record.reason = "context_changed"; }
        if (command == "snapshot" && record !== _active) return fail(command, token, "stale_token");
        if (command != "commit") return project(record, command);
        if (record.phase == "applied") {
            if (params.targetMinutes !== record.targetMinutes) return fail(command, token, "token_conflict");
            return project(record, command);
        }
        if (record.phase == "expired") return project(record, command);
        var weather:WeatherSystem = WeatherSystem.getInstance();
        if (!weather.enableDayNightCycle) return fail(command, token, "cycle_disabled");
        if (!weather.setSleepTime(params.targetMinutes)) return fail(command, token, "clock_unavailable");
        record.targetMinutes = params.targetMinutes;
        record.currentMinutes = params.targetMinutes;
        record.phase = "applied";
        record.owner = null;
        return project(record, command);
    }

    private static function sameContext(record:Object):Boolean {
        return record === _active && record.owner === _root.gameworld.__sleepPanelOwner
            && record.slot === String(_root.savePath) && record.scene === String(_root.关卡标志);
    }
    private static function retireActive():Void {
        if (_active != undefined && _active.phase == "editing") {
            _active.phase = "expired"; _active.reason = "context_changed"; _active.owner = null;
        }
        _active = undefined;
    }
    private static function onSceneChanged():Void { retireActive(); }
    private static function project(record:Object, operation:String):Object {
        var weather:WeatherSystem = WeatherSystem.getInstance();
        var editing:Boolean = record.phase == "editing";
        var enabled:Boolean = editing ? weather.enableDayNightCycle === true : record.cycleEnabled;
        return {
            v:1, operation:operation, token:record.token, phase:record.phase,
            success:record.phase != "expired", changed:record.phase == "applied",
            currentMinutes:record.currentMinutes, targetMinutes:record.targetMinutes,
            cycleEnabled:enabled, cyclePaused:editing ? weather.pauseDayNightCycle === true : record.cyclePaused,
            canSleep:editing && enabled,
            reason:record.phase == "expired" ? "context_changed" : (!enabled ? "cycle_disabled" : "")
        };
    }
    private static function minute(value):Boolean {
        return typeof value == "number" && !isNaN(value) && value >= 0 && value < 1440 && Math.floor(value) == value;
    }
    private static function hasOnly(value:Object, allowed:Array):Boolean {
        for (var key:String in value) {
            var found:Boolean = false;
            for (var i:Number = 0; i < allowed.length; i++) if (allowed[i] == key) found = true;
            if (!found) return false;
        }
        return true;
    }
    private static function fail(operation:String, token:String, error:String):Object {
        return {v:1, success:false, operation:operation, token:token, error:error};
    }
    public static function _resetForTests():Void {
        _active = undefined; _records = {}; _order = [];
    }
}