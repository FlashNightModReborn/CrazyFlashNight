import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.task.TaskUtil;

/** 只读任务选择。taskId + NPC + 驻点 + 地点在确认和关闭后各 fresh 复核一次。 */
class org.flashNight.arki.scene.StageReturnSelection {
    private static var _choice:Object;
    private static var _seq:Number = 0;
    public static function reset():Void { _choice = undefined; }
    public static function isOpen():Boolean { return _choice != undefined; }
    private static function current(choice:Object):Boolean {
        return choice != undefined && _choice === choice && choice.run === StageRunSession.getRunAuthority()
            && choice.worldIdentity === StageReturnFlow.worldIdentity(_root.gameworld) && StageRunSession.canSelectReturn();
    }
    public static function open():Object {
        if (_choice != undefined && _root._webPanelPauseLease == undefined
            && getTimer() > _choice.openDeadline && _choice.plan == undefined) reset();
        if (!StageRunSession.canSelectReturn() || StageReturnFlow.hasStoryReturn()
            || _root._webPanelPauseLease != undefined || _choice != undefined)
            return {success:false, error:"return_selection_unavailable"};
        _seq++;
        _choice = {token:"return.choice." + _seq + "." + getTimer(),
            run:StageRunSession.getRunAuthority(), worldIdentity:StageReturnFlow.worldIdentity(_root.gameworld), options:{}, flight:false, openDeadline:getTimer() + 5000};
        send({task:"panel_request", panel:"tasks", source:"stage_return",
            initData:{view:"stage-return", token:_choice.token}});
        return {success:true, error:""};
    }
    private static function send(message:Object):Void {
        if (_root.server != undefined && typeof _root.server.sendSocketMessage == "function")
            _root.server.sendSocketMessage(new LiteJSON().stringifySafe(message));
    }
    private static function reply(callId:Number, ok:Boolean, error:String, rows:Array, close:Boolean):Void {
        send({task:"task_response", callId:callId, success:ok, error:error,
            choices:rows == undefined ? [] : rows, closePanel:close === true});
    }
    private static function command(params:Object, selecting:Boolean):Boolean {
        if (!current(_choice) || params.token !== _choice.token || typeof params.callId != "number") return false;
        var allowed:Object = {task:true, action:true, callId:true, token:true};
        if (selecting) { allowed.taskId = true; allowed.npcId = true; allowed.placementId = true; allowed.locationId = true; }
        for (var key:String in params) if (allowed[key] !== true) return false;
        return true;
    }
    public static function snapshot(params:Object):Void {
        if (!command(params, false) || _choice.flight) { reply(params.callId, false, "return_selection_stale"); return; }
        _choice.flight = true;
        MapDomainBridge.snapshot(snapshotCallback(_choice, Number(params.callId)), []);
    }
    private static function snapshotCallback(choice:Object, callId:Number):Function {
        return function(ok:Boolean, error:String):Void {
            org.flashNight.arki.scene.StageReturnSelection.snapshotReady(choice, callId, ok, error);
        };
    }
    private static function completeTask(id:String):Boolean {
        var todo:Array = _root.tasks_to_do;
        for (var i:Number = 0; i < todo.length; i++)
            if (String(todo[i].id) == id) return _root.taskCompleteCheck(i) === true;
        return false;
    }
    private static function snapshotReady(choice:Object, callId:Number, ok:Boolean, error:String):Void {
        if (!current(choice)) { reply(callId, false, "return_selection_stale"); return; }
        choice.flight = false;
        if (!ok) { reply(callId, false, error); return; }
        var projection:Object = MapDomainBridge.getProjection();
        var frames:Object = MapDomainBridge.getBootstrap().frames;
        var rows:Array = [];
        choice.options = {};
        for (var i:Number = 0; i < _root.tasks_to_do.length; i++) {
            var id:String = String(_root.tasks_to_do[i].id);
            if (!completeTask(id)) continue;
            var task:Object = TaskUtil.tasks[id];
            var endpoint:Object = projection.taskEndpoints[id].finish;
            var enabled:Boolean = endpoint.returnNavigable === true;
            var row:Object = {taskId:id, title:TaskUtil.getTaskText(task.title),
                npcId:String(endpoint.npcId || ""), npcName:String(endpoint.npcName || task.finish_npc || ""),
                placementId:String(endpoint.placementId || ""), locationId:String(endpoint.locationId || ""),
                location:String(frames[String(endpoint.locationId)] || "地点未登记"),
                enabled:enabled, reason:enabled ? "" : String(endpoint.reason || "交付地点尚不可用")};
            rows.push(row);
            if (enabled) choice.options["$" + id] = row;
        }
        reply(callId, true, "", rows);
    }
    public static function confirm(params:Object):Void {
        if (!command(params, true) || _choice.flight || _choice.plan != undefined) {
            reply(params.callId, false, "return_selection_stale"); return;
        }
        var row:Object = _choice.options["$" + String(params.taskId)];
        if (row == undefined || params.npcId !== row.npcId || params.placementId !== row.placementId
            || params.locationId !== row.locationId || !completeTask(row.taskId)) {
            reply(params.callId, false, "return_selection_stale"); return;
        }
        _choice.flight = true;
        var intent:Object = {kind:"stage_return", taskId:row.taskId, npcId:row.npcId,
            placementId:row.placementId, locationId:row.locationId};
        MapDomainBridge.resolveReturnPlan(intent, planCallback(_choice, Number(params.callId), intent, false), guard(_choice));
    }
    private static function guardCurrent(choice:Object):Boolean {
        var valid:Boolean = current(choice);
        if (!valid && _choice === choice) reset();
        return valid;
    }
    private static function guard(choice:Object):Function {
        return function():Boolean { return org.flashNight.arki.scene.StageReturnSelection.guardCurrent(choice); };
    }
    private static function planCallback(choice:Object, callId:Number, intent:Object, execute:Boolean):Function {
        return function(ok:Boolean, error:String, plan:Object):Void {
            org.flashNight.arki.scene.StageReturnSelection.planReady(choice, callId, intent, execute, ok, error, plan);
        };
    }
    private static function planReady(choice:Object, callId:Number, intent:Object, execute:Boolean,
            ok:Boolean, error:String, plan:Object):Void {
        if (!current(choice)) { if (!execute) reply(callId, false, "return_selection_stale"); return; }
        choice.flight = false;
        if (!ok || !completeTask(String(intent.taskId))) {
            if (execute) { reset(); warn(error || "return_selection_stale"); }
            else reply(callId, false, error || "return_selection_stale");
            return;
        }
        if (!execute) { choice.plan = intent; reply(callId, true, "", undefined, true); return; }
        if (_root._webPanelPauseLease != undefined) { reset(); warn("return_selection_stale"); return; }
        StageReturnFlow.select(plan);
        reset();
        var result:Object = StageRunSession.requestReturnBaseLocal("stage_return_confirm");
        if (result.success !== true) warn(String(result.error));
    }
    public static function onPanelClosed():Void {
        if (_root._webPanelPauseLease != undefined || _choice == undefined) return;
        var choice:Object = _choice;
        if (!current(choice) || choice.plan == undefined || choice.flight) { reset(); return; }
        choice.flight = true;
        MapDomainBridge.resolveReturnPlan(choice.plan, planCallback(choice, 0, choice.plan, true), guard(choice));
    }
    private static function warn(error:String):Void {
        if (typeof _root.发布消息 == "function")
            _root.发布消息("返回未开始，请重新选择交付任务或返回原处。（" + error + "）");
    }
}
