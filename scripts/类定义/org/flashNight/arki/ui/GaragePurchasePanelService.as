import org.flashNight.arki.ui.PanelRequestEnvelope;
import org.flashNight.arki.scene.StageReturnFlow;

/** 车库一次性购车。沿用付费服务的 token 和待保存处理，AS2 保留扣费与基建权威。 */
class org.flashNight.arki.ui.GaragePurchasePanelService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _opened:Object;
    private static var _session:Object;
    private static var _last:Object;
    private static var _lastOwner:Object;
    private static var _lastSlot:String;
    private static var _json:LiteJSON;

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands.garagePurchaseSnapshot = function(params) { org.flashNight.arki.ui.GaragePurchasePanelService.handle("snapshot", params); };
        _root.gameCommands.garagePurchaseCommit = function(params) { org.flashNight.arki.ui.GaragePurchasePanelService.handle("commit", params); };
        _root.gameCommands.garagePurchaseQuery = function(params) { org.flashNight.arki.ui.GaragePurchasePanelService.handle("query", params); };
    }

    private static function vehicleName(id:String):String {
        if (id == "bicycle") return "自行车";
        if (id == "motorcycle") return "摩托车";
        if (id == "offroad") return "越野车";
        return "";
    }

    public static function openPanel(vehicleId:String):Boolean {
        if (vehicleName(vehicleId) == "" || typeof _root.server.sendSocketMessage != "function") return false;
        _opened = {vehicleId:vehicleId, worldIdentity:StageReturnFlow.worldIdentity(_root.gameworld),
            saveOwner:_root.存档系统, slotKey:String(_root.savePath)};
        var sent:Boolean = _root.server.sendSocketMessage(PanelRequestEnvelope.build("garage", "world_garage_purchase", [], [{name:"vehicleId", value:vehicleId}]));
        if (!sent) _opened = null;
        return sent;
    }

    public static function handle(command:String, params:Object):Void {
        var result:Object = execute(command, params);
        result.task = "garage_purchase_response";
        result.callId = Number(params.callId);
        if (_json == undefined) _json = new LiteJSON();
        if (typeof _root.server.sendSocketMessage == "function") _root.server.sendSocketMessage(_json.stringifySafe(result));
    }

    public static function execute(command:String, params:Object):Object {
        if (command != "snapshot" && command != "commit" && command != "query") return fail("unsupported_cmd");
        if (params == null || params.v !== 1) return fail("unsupported_version");
        if (command == "snapshot") return snapshot(params.vehicleId);
        if (typeof params.token != "string") return fail("invalid_payload");
        if (_last != null && params.token === _last.token) {
            if (_lastOwner !== _root.存档系统 || _lastSlot !== String(_root.savePath)) return fail("context_changed");
            if (command == "commit" && params.draft.vehicleId !== _last.vehicleId) return fail("token_conflict");
            return copyResult(_last, command);
        }
        if (_session == null || params.token !== _session.token) return fail("stale_token");
        if (!sameContext()) return fail("context_changed");
        if (command == "query") return state("query");
        return commit(params);
    }

    private static function readVehicle(id:String):Object {
        var name:String = vehicleName(id);
        if (name == "") return null;
        var levels:Array = _root.基建系统.dict[name].Level;
        if (!(levels instanceof Array)) return null;
        var level:Object;
        var purchased:Object;
        for (var i:Number = 0; i < levels.length; i++) {
            if (Number(levels[i].id) == 0) level = levels[i];
            if (Number(levels[i].id) == 1) purchased = levels[i];
        }
        var cost:Number = Number(level.Price);
        if (isNaN(cost) || cost <= 0 || cost > 9007199254740991 || Math.floor(cost) != cost) return null;
        var required:Number = 0;
        if (level.Skill != undefined) {
            if (!(level.Skill instanceof Array) || level.Skill.length != 1 || level.Skill[0].Name != "驾驶") return null;
            required = Number(level.Skill[0].Level);
            if (isNaN(required) || required < 0 || required > 2 || Math.floor(required) != required) return null;
        }
        // 权益使用购买后的 XML 说明；价格与驾驶门槛仍只取待购等级。
        var description:String = purchased == undefined || purchased.Description == undefined
            ? String(level.Description || "") : String(purchased.Description);
        return {id:id, name:name, cost:cost, required:required, description:description};
    }

    private static function contextError():String {
        if (_root.gameworld[_root.控制目标] == undefined) return "actor_unavailable";
        if (_root.基建系统.infrastructure == undefined) return "infrastructure_unavailable";
        if (typeof _root.金钱 != "number" || isNaN(_root.金钱) || _root.金钱 < 0
                || _root.金钱 > 9007199254740991 || Math.floor(_root.金钱) != _root.金钱) return "invalid_balance";
        if (typeof _root.存档系统.markDirty != "function" || typeof _root.存档系统.flushDurableNow != "function") return "save_unavailable";
        if (typeof _root.记录玩家货币变化 != "function") return "currency_unavailable";
        return "";
    }

    private static function drivingLevel():Number {
        var level:Number = Number(_root.主角被动技能.驾驶.等级);
        return isNaN(level) || level < 0 || level > 9007199254740991 ? 0 : Math.floor(level);
    }
    private static function owned():Boolean { return Number(_root.基建系统.infrastructure[_session.vehicle.name]) >= 1; }
    private static function sameContext():Boolean {
        return _session != null && _session.saveOwner === _root.存档系统 && _session.slotKey === String(_root.savePath)
            && (_session.phase == "save_pending" || _session.worldIdentity === StageReturnFlow.worldIdentity(_root.gameworld));
    }

    private static function snapshot(id:String):Object {
        if (_session != null && _session.phase == "save_pending") {
            if (!sameContext()) return fail("context_changed");
            return state("snapshot");
        }
        if (typeof id != "string" || vehicleName(id) == "") return fail("invalid_vehicle");
        if (_opened == null || _opened.vehicleId !== id || _opened.saveOwner !== _root.存档系统
                || _opened.slotKey !== String(_root.savePath) || _opened.worldIdentity !== StageReturnFlow.worldIdentity(_root.gameworld)) return fail("context_changed");
        var invalid:String = contextError();
        if (invalid != "") return fail(invalid);
        var vehicle:Object = readVehicle(id);
        if (vehicle == null) return fail("catalog_invalid");
        _session = {token:"garage." + getTimer() + "." + (++_sequence), vehicle:vehicle,
            worldIdentity:_opened.worldIdentity, saveOwner:_root.存档系统, slotKey:String(_root.savePath), phase:"editing"};
        if (owned()) _session.phase = "owned";
        return state("snapshot");
    }

    private static function state(operation:String):Object {
        var vehicle:Object = _session.vehicle;
        var hasVehicle:Boolean = owned();
        if (hasVehicle && _session.phase == "editing") _session.phase = "owned";
        var result:Object = {success:_session.phase != "save_pending", v:1, operation:operation,
            token:_session.token, phase:_session.phase, vehicleId:vehicle.id, draft:{vehicleId:vehicle.id},
            name:vehicle.name, description:vehicle.description, cost:vehicle.cost, requiredDrivingLevel:vehicle.required,
            drivingLevel:drivingLevel(), balance:Number(_root.金钱), owned:hasVehicle,
            canPurchase:!hasVehicle && _root.金钱 >= vehicle.cost && drivingLevel() >= vehicle.required,
            changed:_session.phase == "save_pending" || _session.phase == "applied", saved:_session.phase == "applied"};
        if (_session.phase == "save_pending") result.error = "save_pending";
        return result;
    }

    private static function commit(params:Object):Object {
        if (params.draft.vehicleId !== _session.vehicle.id) return fail("token_conflict");
        if (_session.phase == "save_pending") return savePrepared();
        var invalid:String = contextError();
        if (invalid != "") return fail(invalid);
        // 拥有状态与资格、余额都在实际扣费前读取；再次确认不会重复购车。
        if (owned()) { _session.phase = "owned"; return finish(); }
        var current:Object = readVehicle(_session.vehicle.id);
        if (current == null) return fail("catalog_invalid");
        if (current.cost != _session.vehicle.cost || current.required != _session.vehicle.required) return fail("catalog_changed");
        if (drivingLevel() < current.required) return fail("driving_required");
        if (_root.金钱 < current.cost) return fail("insufficient_funds");
        _root.存档系统.markDirty();
        _session.phase = "save_pending";
        _root.金钱 -= current.cost;
        _root.基建系统.infrastructure[current.name] = 1;
        var reason:String = current.id == "bicycle" ? "buy_bicycle" : current.id == "motorcycle" ? "buy_motorcycle" : "buy_offroad";
        _root.记录玩家货币变化(-current.cost, 0, {source:"vehicle_service", reason:reason, mergeScope:"operation", operationId:_session.token});
        return savePrepared();
    }

    private static function savePrepared():Object {
        if (!sameContext() || !owned()) return fail("context_changed");
        var saved:Boolean = false;
        saved = _root.存档系统.flushDurableNow("ui.garage_purchase_paid") === true;
        if (saved) { _session.phase = "applied"; return finish(); }
        return state("commit");
    }
    private static function finish():Object {
        var result:Object = state("commit");
        _last = copyResult(result, "commit"); _lastOwner = _session.saveOwner; _lastSlot = _session.slotKey;
        _session = null;
        return result;
    }
    private static function copyResult(source:Object, operation:String):Object {
        var result:Object = {};
        for (var key:String in source) result[key] = source[key];
        result.draft = {vehicleId:source.vehicleId}; result.operation = operation;
        return result;
    }
    private static function fail(error:String):Object { return {success:false, v:1, error:error}; }
    public static function _resetForTests():Void { _opened = null; _session = null; _last = null; _lastOwner = null; _lastSlot = null; }
}
