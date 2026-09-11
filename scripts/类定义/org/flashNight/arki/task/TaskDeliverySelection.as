import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.task.TaskDestinationOptions;

/** 原生常驻交付栏。只选路；不交任务、不发奖励，也不借用关卡返回事务。 */
class org.flashNight.arki.task.TaskDeliverySelection {
    private static var _scope:Object;
    private static var _view:Object;
    private static var _sequence:Number = 0;
    private static var _lastWire:String = "";
    public static function install():Void {
        _root.gameCommands["taskDeliverySync"] = function(params:Object):Void {
            if (params.v !== 1) return;
            org.flashNight.arki.task.TaskDeliverySelection.onMapProjection();
            org.flashNight.arki.task.TaskDeliverySelection.publish(true);
        };
        _root.gameCommands["taskDeliveryAction"] = function(params:Object):Void {
            org.flashNight.arki.task.TaskDeliverySelection.handleAction(params);
        };
    }
    private static function available():Boolean {
        return MapDomainBridge.getProjection() != undefined && !_root.当前为战斗地图
            && !_root.场景转换中 && _root._webPanelPauseLease == undefined
            && StageRunSession.getSceneExitBlockReason() == "";
    }
    private static function scopeCurrent(scope:Object):Boolean {
        return scope != undefined && available() && scope.tasks === _root.tasks_to_do
            && scope.identity === StageReturnFlow.worldIdentity(_root.gameworld)
            && scope.epoch === MapDomainBridge.getSceneEpoch()
            && scope.session == MapDomainBridge.getProjectionToken().split(".")[0]
            && scope.location == String(MapDomainBridge.getProjection().currentLocationId);
    }
    private static function current(view:Object):Boolean {
        return view != undefined && view === _view && view.scope === _scope && scopeCurrent(_scope);
    }
    private static function nextToken():String { _sequence++; return "delivery." + _sequence + "." + getTimer(); }
    public static function onMapProjection():Void {
        if (!available()) { _view = undefined; publish(false); return; }
        if (!scopeCurrent(_scope)) {
            _scope = {id:nextToken(), tasks:_root.tasks_to_do, identity:StageReturnFlow.worldIdentity(_root.gameworld),
                epoch:MapDomainBridge.getSceneEpoch(), session:MapDomainBridge.getProjectionToken().split(".")[0],
                location:String(MapDomainBridge.getProjection().currentLocationId)};
            _view = undefined;
        }
        if (current(_view) && _view.status == "confirming") return;
        var next:Object = TaskDestinationOptions.build(_scope.location, false);
        if (!current(_view) || next.signature != _view.signature)
            _view = {scope:_scope, token:nextToken(), status:"ready", rows:next.rows, options:next.options, signature:next.signature};
        publish(false);
    }
    private static function publish(force:Boolean):Void {
        var valid:Boolean = current(_view);
        var payload:Object = {v:1, scope:valid ? _scope.id : "", options:valid
            ? {status:_view.status, token:_view.token, choices:_view.rows} : {status:"none", token:"", choices:[]}};
        var wire:String = new LiteJSON().stringifySafe(payload);
        if (!force && wire == _lastWire) return;
        if (_root.server.isSocketConnected !== true || typeof _root.server.sendTaskToNode != "function") return;
        _lastWire = wire;
        _root.server.sendTaskToNode("task_delivery", payload, null);
    }
    public static function handleAction(params:Object):Void {
        var keys:Object = {task:true, action:true, v:true, intent:true, choicesToken:true, choiceId:true};
        var count:Number = 0;
        for (var key:String in params) { if (keys[key] !== true) return; count++; }
        if (count != 6 || params.task !== "cmd" || params.action !== "taskDeliveryAction" || params.v !== 1
                || typeof params.choicesToken != "string" || typeof params.choiceId != "string") return;
        var view:Object = _view;
        if (!current(view) || view.status != "ready" || params.choicesToken !== view.token) { onMapProjection(); publish(true); return; }
        if (params.intent === "refresh" && params.choiceId === "") {
            MapDomainBridge.snapshot(function(ok:Boolean, error:String):Void {
                org.flashNight.arki.task.TaskDeliverySelection.onMapProjection();
            }, []);
            return;
        }
        if (params.intent !== "navigate") return;
        var intent:Object = view.options["$" + params.choiceId];
        if (intent == undefined || !TaskDestinationOptions.complete(String(intent.taskId))) { onMapProjection(); publish(true); return; }
        view.status = "confirming"; publish(false);
        MapDomainBridge.navigate(intent, resultCallback(view), flightGuard(view, String(intent.taskId)));
    }
    private static function flightGuard(view:Object, taskId:String):Function {
        return function():Boolean {
            return org.flashNight.arki.task.TaskDeliverySelection.current(view)
                && view.status == "confirming" && org.flashNight.arki.task.TaskDestinationOptions.complete(taskId);
        };
    }
    private static function resultCallback(view:Object):Function {
        return function(ok:Boolean, error:String):Void {
            org.flashNight.arki.task.TaskDeliverySelection.finish(view, ok, error);
        };
    }
    private static function finish(view:Object, ok:Boolean, error:String):Void {
        if (_view !== view) return;
        _view = undefined;
        onMapProjection();
        if (!ok && typeof _root.发布消息 == "function") _root.发布消息("交付地点已变化或当前无法前往，请重新选择任务。");
    }
}
