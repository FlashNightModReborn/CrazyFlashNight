import org.flashNight.arki.unit.CharacterIdentityRules;
import org.flashNight.arki.ui.PanelRequestEnvelope;
import org.flashNight.arki.unit.UnitComponent.Dressup.LiveAppearanceUpdater;

/** 医务室整形领域。一个 AS2 token 只接受一次身份写与扣费；保存重试不重放业务写。 */
class org.flashNight.arki.ui.PlasticSurgeryPanelService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _session:Object = null;
    private static var _last:Object = null;
    private static var _json:LiteJSON;
    private static var COST:Number = 5;
    private static var SLOTS:Array = ["头部装备", "上装装备", "下装装备", "手部装备", "脚部装备", "颈部装备", "长枪", "手枪", "手枪2", "刀", "手雷"];

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["plasticSurgerySnapshot"] = function(params) { org.flashNight.arki.ui.PlasticSurgeryPanelService.handle("snapshot", params); };
        _root.gameCommands["plasticSurgeryCommit"] = function(params) { org.flashNight.arki.ui.PlasticSurgeryPanelService.handle("commit", params); };
        _root.gameCommands["plasticSurgeryQuery"] = function(params) { org.flashNight.arki.ui.PlasticSurgeryPanelService.handle("query", params); };
    }

    public static function openPanel():Boolean {
        if (typeof _root.server.sendSocketMessage != "function") return false;
        return _root.server.sendSocketMessage(PanelRequestEnvelope.build("surgery", "world_plastic_surgery", [], []));
    }

    public static function handle(command:String, params:Object):Void {
        var result:Object = execute(command, params);
        result.task = "plastic_surgery_response";
        result.callId = Number(params.callId);
        if (_json == undefined) _json = new LiteJSON();
        if (typeof _root.server.sendSocketMessage == "function") _root.server.sendSocketMessage(_json.stringifySafe(result));
    }

    public static function execute(command:String, params:Object):Object {
        if (command != "snapshot" && command != "commit" && command != "query") return fail("unsupported_cmd");
        if (params == null || params.v !== 1) return fail("unsupported_version");
        if (command == "snapshot") return snapshot();
        if (typeof params.token != "string") return fail("invalid_payload");
        if (_last != null && params.token === _last.token) {
            if (command == "commit" && !CharacterIdentityRules.same(params.draft, _last.current)) return fail("token_conflict");
            return copyResult(_last, command);
        }
        if (_session == null || params.token !== _session.token) return fail("stale_token");
        if (command == "query") {
            if (!sameContext()) return fail("context_changed");
            return resultForSession("query");
        }
        return commit(params);
    }

    private static function profile():Object {
        return {characterName:String(_root.角色名), gender:_root.性别 == "女" ? "female" : "male", height:Number(_root.身高)};
    }

    private static function contextError():String {
        var actor:Object = _root.gameworld[_root.控制目标];
        if (!LiveAppearanceUpdater.isReady(actor)) return "actor_unavailable";
        if (_root.性别 != "男" && _root.性别 != "女") return "invalid_gender";
        var invalid:String = CharacterIdentityRules.validate(profile());
        if (invalid != "") return invalid;
        if (typeof _root.虚拟币 != "number" || isNaN(_root.虚拟币)
                || _root.虚拟币 < 0 || _root.虚拟币 > 9007199254740991 || Math.floor(_root.虚拟币) != _root.虚拟币) return "invalid_balance";
        if (typeof _root.存档系统.markDirty != "function"
                || typeof _root.存档系统.flushDurableNow != "function") return "save_unavailable";
        if (typeof _root.记录玩家货币变化 != "function") return "currency_unavailable";
        return "";
    }

    private static function sameContext():Boolean {
        if (_session == null || _session.saveOwner !== _root.存档系统
                || _session.slotKey !== String(_root.savePath)) return false;
        if (_session.phase == "save_pending") return CharacterIdentityRules.same(profile(), _session.draft);
        return _session.actor === _root.gameworld[_root.控制目标] && _session.world === _root.gameworld;
    }

    private static function snapshot():Object {
        var invalid:String = contextError();
        if (invalid != "") return fail(invalid);
        if (_session != null && _session.phase == "save_pending") {
            if (!sameContext()) return fail("context_changed");
            return resultForSession("snapshot");
        }
        _session = {
            token:"surgery." + getTimer() + "." + (++_sequence),
            actor:_root.gameworld[_root.控制目标], world:_root.gameworld, saveOwner:_root.存档系统,
            baseline:profile(), draft:profile(), phase:"editing", slotKey:String(_root.savePath)
        };
        return resultForSession("snapshot");
    }

    private static function portrait():Object {
        var actor:Object = _root.gameworld[_root.控制目标];
        var equipment:Object = {};
        for (var i:Number = 0; i < SLOTS.length; i++) {
            var item:Object = actor[SLOTS[i]];
            if (item != null && typeof item.name == "string") equipment[SLOTS[i]] = String(item.name);
        }
        return {equipment:equipment, hair:String(_root.发型), face:String(_root.脸型)};
    }

    private static function resultForSession(operation:String):Object {
        var value:Object = {
            success:true, v:1, operation:operation, token:_session.token, phase:_session.phase,
            current:profile(), draft:CharacterIdentityRules.copy(_session.draft),
            cost:COST, balance:Number(_root.虚拟币), portrait:portrait(),
            changed:_session.phase != "editing", saved:_session.phase == "applied"
        };
        if (_session.phase == "save_pending") { value.success = false; value.error = "save_pending"; }
        return value;
    }

    private static function commit(params:Object):Object {
        var invalid:String = CharacterIdentityRules.validate(params.draft);
        if (invalid != "") return fail(invalid);
        if (!sameContext()) return fail("context_changed");
        if (_session.phase != "editing") {
            if (!CharacterIdentityRules.same(params.draft, _session.draft)) return fail("token_conflict");
            return savePrepared();
        }
        invalid = contextError();
        if (invalid != "") return fail(invalid);
        if (!CharacterIdentityRules.same(profile(), _session.baseline)) return fail("stale_state");
        if (CharacterIdentityRules.same(profile(), params.draft)) return fail("no_change");
        if (_root.虚拟币 < COST) return fail("insufficient_funds");

        try { _root.存档系统.markDirty(); } catch (dirtyError) { return fail("save_unavailable"); }
        var old:Object = captureIdentity();
        // 外观代码可能调用装备订阅者；领域边界捕获异常并恢复身份，不进入完整单位初始化。
        try {
            applyIdentity(params.draft);
            if (!LiveAppearanceUpdater.refresh(_session.actor)) throw new Error("appearance_refresh_failed");
        } catch (refreshError) {
            restoreIdentity(old);
            try { LiveAppearanceUpdater.refresh(_session.actor); } catch (restoreError) { }
            return fail("refresh_failed");
        }
        _session.draft = CharacterIdentityRules.copy(params.draft);
        _session.phase = "save_pending";
        // 后续只保存同槽已应用资料，不持有已离场 MovieClip，也不再刷新或扣费。
        _session.actor = null; _session.world = null;
        _root.虚拟币 -= COST;
        // 播报是已提交事实的消费者；失败不能让已扣费操作重放。
        try {
            _root.记录玩家货币变化(0, -COST, {source:"appearance_service", reason:"plastic_surgery", mergeScope:"operation", operationId:_session.token});
        } catch (feedError) { trace("[PlasticSurgery] currency feed failed after commit"); }
        try { if (typeof _root.获取虚拟币值 == "function") _root.获取虚拟币值(); }
        catch (balanceUiError) { trace("[PlasticSurgery] balance display remains stale"); }
        return savePrepared();
    }

    private static function savePrepared():Object {
        // 重试只执行同一份已应用状态的保存，绝不再次扣费、换皮或随机化。
        if (!CharacterIdentityRules.same(profile(), _session.draft)) return fail("context_changed");
        var saved:Boolean = false;
        try { saved = _root.存档系统.flushDurableNow("ui.plastic_surgery_paid") === true; }
        catch (saveError) { trace("[PlasticSurgery] save remains pending"); }
        if (saved) _session.phase = "applied";
        var response:Object = resultForSession("commit");
        if (saved) { _last = copyResult(response, "commit"); _session = null; }
        return response;
    }

    private static function applyIdentity(draft:Object):Void {
        _root.角色名 = draft.characterName;
        _root.性别 = draft.gender == "female" ? "女" : "男";
        _root.身高 = draft.height;
        _root.脸型 = _root.性别 + "变装-基本脸型";
        _session.actor.名字 = _root.角色名;
        _session.actor.性别 = _root.性别;
        _session.actor.身高 = _root.身高;
        _session.actor.脸型 = _root.脸型;
    }

    private static function captureIdentity():Object {
        var actor:Object = _session.actor;
        return {rootName:_root.角色名, rootGender:_root.性别, rootHeight:_root.身高, rootFace:_root.脸型,
            name:actor.名字, gender:actor.性别, height:actor.身高, face:actor.脸型,
            hp:actor.hp, mp:actor.mp};
    }

    private static function restoreIdentity(old:Object):Void {
        _root.角色名 = old.rootName; _root.性别 = old.rootGender; _root.身高 = old.rootHeight; _root.脸型 = old.rootFace;
        var actor:Object = _session.actor;
        actor.名字 = old.name; actor.性别 = old.gender; actor.身高 = old.height; actor.脸型 = old.face;
        actor.hp = old.hp; actor.mp = old.mp;
    }

    private static function copyResult(source:Object, operation:String):Object {
        var result:Object = {};
        for (var key:String in source) if (key != "task" && key != "callId") result[key] = source[key];
        result.operation = operation;
        result.current = CharacterIdentityRules.copy(source.current);
        result.draft = CharacterIdentityRules.copy(source.draft);
        return result;
    }

    private static function fail(error:String):Object { return {success:false, v:1, error:error}; }
    public static function _resetForTests():Void { _session = null; _last = null; }
}
