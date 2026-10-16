import org.flashNight.arki.scene.BookRunClock;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageReturnFlow;

/** 只观察本轮原生战斗；无存档、回血、冷却、输入或奖励写入。 */
class org.flashNight.arki.scene.LeeTrialTelemetry {
    private static var _record:Object;
    private static var _owner:Object;
    private static var _room:Object;
    private static var _watch:MovieClip;
    private static var _lastAction:Object;

    public static function install():Void {
        if (_root.Lee试战 == undefined) _root.Lee试战 = {};
        _root.Lee试战.资源记录 = function():String {
            var codec:LiteJSON = new LiteJSON();
            return codec.stringifySafe(org.flashNight.arki.scene.LeeTrialTelemetry.snapshot());
        };
    }
    private static function matches(run:Object):Boolean {
        return _record != null && run.bookId === "lee-trial" && run.slot === _record.slot
            && String(_root.savePath) === _record.slot && run.startedAt === _record.startedAt
            && run.seed === _record.seed;
    }
    public static function beginRoom(world:Object, identity:Object):Void {
        var run:Object = _root._saveExt.bookRun;
        var index:Number = StageManager.getInstance().currentStage;
        if (run.bookId !== "lee-trial" || run.outcome !== "active" || run.slot !== String(_root.savePath)
                || _root.当前为战斗地图 !== true || world !== _root.gameworld
                || identity == null || identity !== StageReturnFlow.worldIdentity(world)
                || isNaN(index) || index < 0 || !(index < 4)) return;
        var actor:Object = world[_root.控制目标];
        if (actor.__enemyActionPlayer !== true || isNaN(actor.hp) || !(actor.hp > 0)
                || isNaN(actor.hp满血值) || !(actor.hp满血值 > 0)) return;
        if (!matches(run)) {
            var config:Object = org.flashNight.arki.scene.LeeTrialDefinition.get();
            _record = {schema:"lee-resource-observation.v1", slot:String(_root.savePath),
                startedAt:run.startedAt, seed:run.seed, outcome:"active",
                actor:org.flashNight.gesh.object.PersistedSnapshot.clone(config.actor), rooms:[]};
            _room = null;
        }
        if (_owner === identity && _room.index === index) return;
        closeRoom("left");
        var prior:Object = _record.rooms[_record.rooms.length - 1];
        _room = {index:index, entryHp:Number(actor.hp), endHp:Number(actor.hp),
            minHp:Number(actor.hp), maxHp:Number(actor.hp满血值), level:Number(actor.等级),
            entryMs:BookRunClock.elapsed(run), elapsedMs:0, observedHpLoss:0,
            observedHpGain:0, samples:0, cleared:false, outcome:"active", actions:{}};
        if (prior != null) _room.carryDelta = _room.entryHp - prior.endHp;
        _record.rooms.push(_room);
        _owner = identity; _lastAction = null;
        if (_watch == null || _watch._name == undefined)
            _watch = _root.createEmptyMovieClip("__leeResourceObservation", _root.getNextHighestDepth());
        _watch.onEnterFrame = function():Void { org.flashNight.arki.scene.LeeTrialTelemetry.tick(); };
        tick();
    }
    /** 差分仅代表两次逐帧采样之间的可见HP变化，不冒充精确伤害或治疗。 */
    public static function observe(room:Object, hp:Number, elapsed:Number):Void {
        if (isNaN(hp) || isNaN(elapsed)) return;
        var current:Number = Math.max(0, hp);
        var difference:Number = room.endHp - current;
        if (difference > 0) room.observedHpLoss += difference;
        else if (difference < 0) room.observedHpGain -= difference;
        room.endHp = current;
        room.minHp = Math.min(room.minHp, current);
        var activeElapsed:Number = Math.max(room.elapsedMs, elapsed - room.entryMs);
        if (current == 0 && room.firstDeathMs == undefined) room.firstDeathMs = activeElapsed;
        // 等待玩家选择返回的时间不计入本轮资源存活时间。
        room.elapsedMs = room.firstDeathMs == undefined ? activeElapsed : room.firstDeathMs;
        room.samples++;
    }
    public static function tick():Void {
        if (_record.outcome !== "active" || _room == null) { stop(); return; }
        var run:Object = _root._saveExt.bookRun;
        if (!matches(run) || run.outcome !== "active") { stop(); return; }
        // MovieClip路径可复用；普通对象身份必须与本次揭幕后捕获的一致。
        if (_owner !== StageReturnFlow.worldIdentity(_root.gameworld) || _root.当前为战斗地图 !== true) return;
        var actor:Object = _root.gameworld[_root.控制目标];
        if (actor.__enemyActionPlayer !== true) return;
        observe(_room, Number(actor.hp), BookRunClock.elapsed(run));
        var token:Object = actor.__enemyActionRuntime.active;
        if (token != null && token !== _lastAction) {
            var key:String = String(token.actionId);
            _room.actions[key] = Number(_room.actions[key] || 0) + 1;
        }
        _lastAction = token;
        if (!_room.cleared && _root.gameworld.允许通行 === true) {
            _room.cleared = true;
            _room.clearHp = _room.endHp;
            _room.clearMs = _room.elapsedMs;
            announce(_room);
        }
    }
    private static function announce(room:Object):Void {
        _root.发布消息("资源基线 " + (room.index + 1) + "/4：HP " + Math.round(room.entryHp)
            + " → " + Math.round(room.endHp) + "，最低 " + Math.round(room.minHp)
            + "，" + (Math.round(room.elapsedMs / 100) / 10) + "秒");
    }
    private static function closeRoom(outcome:String):Void {
        if (_room != null && _room.outcome === "active") _room.outcome = outcome;
    }
    public static function finish(outcome:String):Void {
        if (!matches(_root._saveExt.bookRun) || _record.outcome !== "active") return;
        tick();
        closeRoom(outcome);
        if (_room != null) {
            if (outcome === "victory") { _room.cleared = true; _room.clearHp = _room.endHp; _room.clearMs = _room.elapsedMs; }
            announce(_room);
        }
        _record.outcome = outcome;
        _record.elapsedMs = BookRunClock.elapsed(_root._saveExt.bookRun);
        stop();
    }
    private static function stop():Void {
        delete _watch.onEnterFrame;
    }
    public static function snapshot():Object {
        return _record == null ? null : org.flashNight.gesh.object.PersistedSnapshot.clone(_record);
    }
}
