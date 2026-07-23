

/**
 * 基地理发店 Web Panel 的窄 AS2 权威服务。
 *
 * 目录只读取现役 _root 三数组；Web 预览保持纯本地，唯一写入口是 commit。
 * 当前生产目录全部免费，若发现任一非零价格则整体拒绝，避免意外引入半套支付语义。
 */
class org.flashNight.arki.ui.HairdresserPanelService {
    private static var _installed:Boolean = false;
    private static var _json:LiteJSON;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["hairdresserSnapshot"] = function(params) {
            org.flashNight.arki.ui.HairdresserPanelService.handle("snapshot", params);
        };
        _root.gameCommands["hairdresserCommit"] = function(params) {
            org.flashNight.arki.ui.HairdresserPanelService.handle("commit", params);
        };
        _root.gameCommands["openHairdresser"] = function():Boolean {
            return org.flashNight.arki.ui.HairdresserPanelService.openPanel();
        };
    }

    public static function openPanel():Boolean {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) {
            return false;
        }
        var payload:String = org.flashNight.arki.ui.PanelRequestEnvelope.build(
            "hairdresser", "world_hairdresser", [], []
        );
        return _root.server.sendSocketMessage(payload);
    }

    public static function handle(commandName:String, params:Object):Void {
        var request:Object = params == undefined ? {} : params;
        var callId:Number = Number(request.callId);
        if (isNaN(callId)) callId = 0;
        var response:Object = execute(commandName, request);
        response.task = "hairdresser_response";
        response.callId = callId;
        sendResponse(response);
    }

    public static function execute(commandName:String, params:Object):Object {
        if (commandName != "snapshot" && commandName != "commit") {
            return fail("unsupported_cmd");
        }
        if (params == undefined || params.v !== 1) return fail("unsupported_version");
        if (commandName == "snapshot") return executeSnapshot();
        return executeCommit(params);
    }

    private static function executeSnapshot():Object {
        var resolved:Object = resolveCatalog();
        if (!resolved.success) return resolved;
        return {
            success:true,
            v:1,
            gender:_root.性别 == undefined ? "" : String(_root.性别),
            face:_root.脸型 == undefined ? "" : String(_root.脸型),
            currentHair:_root.发型 == undefined ? "" : String(_root.发型),
            catalog:resolved.catalog
        };
    }

    private static function executeCommit(params:Object):Object {
        var resolved:Object = resolveCatalog();
        if (!resolved.success) return resolved;
        if (typeof params.hairIdentifier != "string" || String(params.hairIdentifier) == "") {
            return fail("invalid_payload");
        }

        var hairIdentifier:String = String(params.hairIdentifier);
        var found:Boolean = false;
        for (var i:Number = 0; i < resolved.catalog.length; i++) {
            if (String(resolved.catalog[i].identifier) == hairIdentifier) {
                found = true;
                break;
            }
        }
        if (!found) return fail("hair_not_found");

        if (_root.gameworld == undefined || _root.控制目标 == undefined) {
            return fail("actor_unavailable");
        }
        var actor:Object = _root.gameworld[_root.控制目标];
        if (actor == undefined) return fail("actor_unavailable");
        if (_root.存档系统 == undefined || typeof _root.存档系统 != "object") {
            return fail("save_unavailable");
        }
        if (typeof actor.gotoAndPlay != "function") return fail("refresh_unavailable");

        // 所有依赖先验证完毕，再一次性写持久字段、live actor 与 dirty mark。
        _root.发型 = hairIdentifier;
        actor.发型 = hairIdentifier;
        actor.gotoAndPlay("刷新装扮");
        _root.存档系统.dirtyMark = true;
        return {success:true, v:1, operation:"commit", currentHair:hairIdentifier};
    }

    private static function resolveCatalog():Object {
        var identifiers:Object = _root.发型库;
        var names:Object = _root.发型名称库;
        var prices:Object = _root.发型价格;
        if (!(identifiers instanceof Array) || !(names instanceof Array)
                || !(prices instanceof Array) || identifiers.length == 0
                || identifiers.length != names.length || identifiers.length != prices.length) {
            return fail("catalog_invalid");
        }

        var catalog:Array = [];
        for (var i:Number = 0; i < identifiers.length; i++) {
            if (identifiers[i] == undefined || names[i] == undefined) {
                return fail("catalog_invalid");
            }
            var identifier:String = String(identifiers[i]);
            var name:String = String(names[i]);
            var price:Number = Number(prices[i]);
            if (identifier == "" || isNaN(price)) return fail("catalog_invalid");
            if (price != 0) return fail("pricing_unsupported");
            // 保留源数组顺序和重复行；目录身份不能由 Web 或本服务去重。
            catalog.push({identifier:identifier, name:name});
        }
        return {success:true, catalog:catalog};
    }

    private static function fail(errorCode:String):Object {
        return {success:false, error:errorCode};
    }

    private static function sendResponse(response:Object):Void {
        if (_root.server == undefined || _root.server.sendSocketMessage == undefined) return;
        if (_json == undefined) _json = new LiteJSON();
        _root.server.sendSocketMessage(_json.stringify(response));
    }
}
