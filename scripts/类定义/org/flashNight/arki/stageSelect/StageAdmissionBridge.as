import org.flashNight.neur.Server.ServerManager;
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.stageSelect.StageAdmissionFacts;
import org.flashNight.arki.scene.StageRunSession;

/** Owns only the Flash end of a host-issued, single-use grant. No unlock predicates live here. */
class org.flashNight.arki.stageSelect.StageAdmissionBridge {
    private static var _json:LiteJSON = new LiteJSON();
    private static var _fields:Array = ["url","Type","Name","FadeTransitionFrame","RootFadeTransitionFrame","Address","StartFrame","EndFrame","Limitation","LimitLevel","UnlockCondition","AltUnlockCondition","UnlockRule"];
    private static var _binding:Object;
    private static var _flight:Object;
    private static var _epoch:Number = 0;
    private static var _panelEpoch:Number = 0;
    private static var _sequence:Number = 0;
    private static var _receipts:Object = {};
    private static var _order:Array = [];
    private static var _cancelled:Object = {};
    private static var _uncertainSlot:String;

    public static function panelClosed():Void { _panelEpoch++; }
    public static function reset():Void {
        _uncertainSlot = null;
        _epoch++; _panelEpoch++; _binding = null; _flight = null; _receipts = {}; _order = []; _cancelled = {};
    }
    public static function nextId():String { return "stage.op." + getTimer() + "." + (++_sequence); }

    private static function row(name:String):Object {
        var info:Object = _root.StageInfoDict[name];
        if (info == null) return null;
        var result:Object = {};
        for (var i:Number = 0; i < _fields.length; i++) {
            var key:String = _fields[i];
            if (info[key] !== undefined) result[key] = info[key];
        }
        return result;
    }
    private static function samePlayer(ctx:Object):Boolean {
        return ctx.epoch == _epoch && ctx.slot === String(_root.savePath)
            && ctx.player === _root.存档系统 && ctx.dict === _root.StageInfoDict
            && ctx.boot === MapDomainBridge.getBootstrap() && ServerManager.getInstance().isSocketConnected;
    }
    private static function current(ctx:Object):Boolean {
        if (!samePlayer(ctx) || ctx.binding !== _binding || getTimer() >= ctx.deadline
                || ctx.scene !== MapDomainBridge.getSceneEpoch() || ctx.world !== _root.gameworld
                || ctx.hero !== _root.gameworld[_root.控制目标] || !StageAdmissionFacts.ready()
                || _cancelled[ctx.owner] !== undefined || (ctx.panel && (ctx.panelEpoch != _panelEpoch
                    || (ctx.enter && ctx.lease !== _root._webPanelPauseLease)))
                || (ctx.guard != null && ctx.guard() !== true)) return false;
        for (var i:Number = 0; i < ctx.names.length; i++) {
            var name:String = ctx.names[i];
            var actual:Object = row(name);
            if (actual == null ? ctx.binding.rows[name] !== undefined : ctx.binding.rows[name] !== _json.stringifySafe(actual)) return false;
        }
        return true;
    }
    private static function send(message:Object, cb:Function):Void {
        ServerManager.getInstance().sendTaskWithCallback("stage_admission", message, null, cb, 4500);
    }
    private static function envelope(ctx:Object, op:String):Object {
        return {version:1, op:op, slot:ctx.slot, catalog:ctx.binding.catalog, binding:ctx.binding.id,
            taskDigest:ctx.boot.contentDigest, operation:ctx.id};
    }

    public static function request(names:Array, kind:String, difficulty:String, id:String,
            owner:String, enter:Boolean, guard:Function, callback:Function, selector:Object):Void {
        if (enter && _uncertainSlot != null && _uncertainSlot === String(_root.savePath)) {
            callback(null, "stage_delivery_unknown"); return;
        }
        var boot:Object = MapDomainBridge.getBootstrap();
        if (!StageAdmissionFacts.ready() || boot == null || _root.StageInfoDict == null
                || !ServerManager.getInstance().isSocketConnected) { callback(null, "stage_facts_unavailable"); return; }
        var ctx:Object = {id:id, names:names.slice(), kind:kind, difficulty:difficulty, owner:owner,
            enter:enter, guard:guard, callback:callback, selector:selector, epoch:_epoch, panelEpoch:_panelEpoch,
            panel:owner.indexOf("legacy.") != 0, lease:_root._webPanelPauseLease, scene:MapDomainBridge.getSceneEpoch(), slot:String(_root.savePath),
            boot:boot, world:_root.gameworld, hero:_root.gameworld[_root.控制目标], player:_root.存档系统,
            dict:_root.StageInfoDict, deadline:getTimer()+14000};
        if (_binding != null && samePlayer(_binding)) { prepare(ctx, _binding); return; }
        if (_flight != null && samePlayer(_flight)) { _flight.waiters.push(ctx); return; }
        var projection:Object = {};
        var signatures:Object = {};
        for (var name:String in ctx.dict) {
            projection[name] = row(name); signatures[name] = _json.stringifySafe(projection[name]);
        }
        var flight:Object = {epoch:_epoch, boot:boot, slot:ctx.slot, player:ctx.player, dict:ctx.dict,
            rows:signatures, waiters:[ctx]};
        _flight = flight;
        send({version:1, op:"bind", slot:ctx.slot, taskDigest:boot.contentDigest, mapSession:boot.sessionToken,
            playerEpoch:_epoch, projection:projection},
            function(reply:Object):Void { org.flashNight.arki.stageSelect.StageAdmissionBridge.onBind(flight, reply); });
    }
    private static function onBind(flight:Object, reply:Object):Void {
        var ok:Boolean = _flight === flight && samePlayer(flight) && reply.success === true
            && typeof reply.result.binding == "string" && typeof reply.result.catalog == "string"
            && reply.result.taskDigest === flight.boot.contentDigest;
        if (_flight === flight) _flight = null;
        if (ok) { flight.id = reply.result.binding; flight.catalog = reply.result.catalog; _binding = flight; }
        var waiters:Array = flight.waiters;
        delete flight.waiters;
        for (var i:Number = 0; i < waiters.length; i++) {
            if (ok) prepare(waiters[i], flight);
            else finish(waiters[i], null, String(reply.error || "stage_catalog_mismatch"));
        }
    }
    private static function finish(ctx:Object, result:Object, error:String):Void {
        if (ctx.done) return;
        ctx.done = true;
        if (error == "admission_binding_expired" && ctx.binding === _binding) _binding = null;
        ctx.callback(result, error);
    }
    private static function prepare(ctx:Object, binding:Object):Void {
        ctx.binding = binding;
        if (!current(ctx)) { finish(ctx, null, "stage_state_changed"); return; }
        var message:Object = envelope(ctx, "prepare");
        message.intent = ctx.enter ? "enter" : "snapshot";
        message.kind = ctx.kind; message.difficulty = ctx.difficulty; message.names = ctx.names;
        message.owner = ctx.owner; message.scene = ctx.scene;
        if (ctx.selector != null) message.selector = ctx.selector;
        send(message, function(reply:Object):Void { org.flashNight.arki.stageSelect.StageAdmissionBridge.sample(ctx, reply); });
    }
    private static function sample(ctx:Object, reply:Object):Void {
        if (reply.success !== true || reply.result.operation !== ctx.id || !current(ctx)) {
            finish(ctx, null, String(reply.error || "stage_state_changed")); return;
        }
        ctx.scope = reply.result.scope;
        var sample:Object = StageAdmissionFacts.capture(ctx.scope);
        if (sample == null) { finish(ctx, null, "stage_facts_unavailable"); return; }
        ctx.signature = _json.stringifySafe(sample);
        var message:Object = envelope(ctx, "decide");
        message.facts = sample.facts; message.challenge = sample.challenge; message.force = sample.force;
        message.owner = ctx.owner; message.scene = ctx.scene;
        send(message, function(result:Object):Void { org.flashNight.arki.stageSelect.StageAdmissionBridge.decided(ctx, result); });
    }
    private static function decided(ctx:Object, reply:Object):Void {
        var result:Object = reply.result;
        if (reply.success !== true || result.operation !== ctx.id || !current(ctx)) {
            finish(ctx, null, String(reply.error || "stage_state_changed")); return;
        }
        if (!ctx.enter) {
            if (ctx.signature !== _json.stringifySafe(StageAdmissionFacts.capture(ctx.scope))) {
                finish(ctx, null, "stage_state_changed"); return;
            }
            result.catalog = ctx.binding.catalog;
            finish(ctx, result, ""); return;
        }
        if (result.binding !== ctx.binding.id || result.catalog !== ctx.binding.catalog || result.state !== "granted"
                || result.stage !== ctx.names[0] || result.difficulty !== ctx.difficulty || result.kind !== ctx.kind
                || result.owner !== ctx.owner || result.scene !== ctx.scene || _receipts[ctx.id] != null) {
            finish(ctx, null, "invalid_stage_grant"); return;
        }
        ctx.state = "granted"; _receipts[ctx.id] = ctx; _order.push(ctx.id);
        prune(); finish(ctx, ctx, "");
        delete ctx.callback;
    }
    private static function prune():Void {
        for (var i:Number = _order.length - 1; i >= 0; i--) {
            var ctx:Object = _receipts[_order[i]];
            if (ctx.deadline+120000 < getTimer() && !(ctx.state == "committed" && StageRunSession.isStageStartReservationValid(ctx.id))) {
                delete _receipts[_order[i]]; _order.splice(i,1);
            }
        }
    }
    /** The panel may close, time out or be replaced while Flash is loading the stage XML.
        Ask its owning host again, then re-sample locally in the same turn as the fade. */
    public static function afterLoad(ctx:Object, loaded:Function, rejected:Function):Function {
        return function(data:Object):Void {
            if (ctx.loadAwaited || ctx.state != "granted") return;
            ctx.loadAwaited = true;
            if (ctx.guard != null && ctx.guard() !== true) { rejected("stage_load_failed"); return; }
            if (!current(ctx)) { rejected("stage_state_changed"); return; }
            var message:Object = envelope(ctx, "confirm_load");
            message.scene = ctx.scene; message.owner = ctx.owner;
            send(message, function(reply:Object):Void {
                if (ctx.state != "granted") return;
                if (reply.success !== true || reply.result.state !== "load_confirmed"
                        || reply.result.operation !== ctx.id || reply.result.binding !== ctx.binding.id || !current(ctx)) {
                    rejected("stage_state_changed"); return;
                }
                ctx.loadConfirmed = true;
                loaded(data);
            });
        };
    }
    public static function seal(ctx:Object):Boolean {
        if (ctx == null || _receipts[ctx.id] !== ctx || ctx.state !== "granted" || !current(ctx)
                || (ctx.loadAwaited && !ctx.loadConfirmed)
                || ctx.signature !== _json.stringifySafe(StageAdmissionFacts.capture(ctx.scope))) return false;
        outcome(ctx, "sealed"); return true;
    }
    public static function outcome(ctx:Object, state:String):Void {
        if (ctx == null || _receipts[ctx.id] !== ctx || ctx.state == state) return;
        ctx.state = state;
        if (state == "unknown") _uncertainSlot = ctx.slot;
        var message:Object = envelope(ctx, "outcome"); message.state = state;
        send(message, function(reply:Object):Void {});
    }
    public static function canBegin(id:String):Boolean {
        var ctx:Object = _receipts[id];
        return ctx != null && ctx.state == "committed" && ctx.epoch == _epoch && ctx.slot === String(_root.savePath);
    }
    public static function started(id:String):Void { if (canBegin(id)) outcome(_receipts[id], "started"); }
    public static function statusFor(owner:String):String {
        var now:Number = getTimer();
        for (var key:String in _cancelled) if (_cancelled[key] < now) delete _cancelled[key];
        _cancelled[owner] = now + 16000;
        for (var i:Number = _order.length - 1; i >= 0; i--) {
            var ctx:Object = _receipts[_order[i]];
            if (ctx.owner === owner) return String(ctx.state);
        }
        return "unknown";
    }
}
