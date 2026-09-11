import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.task.TaskUtil;

/** 原生结算栏的只读选项；选中不导航，按钮确认时 fresh 求解精确任务端点。 */
class org.flashNight.arki.scene.StageReturnOptions {
    private static var _view:Object;
    private static var _seq:Number = 0;
    public static function reset():Void { _view = undefined; }
    public static function isBusy():Boolean { return current(_view) && _view.status == "confirming"; }
    private static function available():Boolean {
        return StageRunSession.canSelectReturn() && !StageReturnFlow.hasStoryReturn();
    }
    private static function current(view:Object):Boolean {
        return view != undefined && view === _view && available()
            && view.run === StageRunSession.getRunAuthority()
            && view.identity === StageReturnFlow.worldIdentity(_root.gameworld);
    }
    public static function projection():Object {
        if (!available()) return {status:"none", token:"", choices:[]};
        if (!current(_view)) return {status:"loading", token:"", choices:[]};
        return {status:_view.status, token:_view.token, choices:_view.rows};
    }
    /** 在状态发送后启动异步采样，避免同步回调使旧 revision 覆盖新投影。 */
    public static function refresh():Void {
        if (!available()) { reset(); return; }
        if (current(_view)) return;
        _seq++;
        var view:Object = {run:StageRunSession.getRunAuthority(),
            identity:StageReturnFlow.worldIdentity(_root.gameworld),
            token:"return.options." + _seq + "." + getTimer(), status:"loading", rows:[], options:{}};
        _view = view;
        MapDomainBridge.snapshot(function(ok:Boolean, error:String):Void {
            org.flashNight.arki.scene.StageReturnOptions.ready(view, ok, error);
        }, []);
    }
    private static function complete(id:String):Boolean {
        for (var i:Number = 0; i < _root.tasks_to_do.length; i++)
            if (String(_root.tasks_to_do[i].id) == id) return _root.taskCompleteCheck(i) === true;
        return false;
    }
    private static function ready(view:Object, ok:Boolean, error:String):Void {
        if (!current(view)) return;
        view.status = ok ? "ready" : "error";
        if (ok) {
            buildRows(view);
        }
        StageRunSession.notifyReturnOptionsChanged();
    }
    private static function buildRows(view:Object):Void {
        var bootstrap:Object = MapDomainBridge.getBootstrap();
        var origin:String = String(bootstrap.locationByFrame[String(StageReturnFlow.originFrame())] || "");
        var next:Object = org.flashNight.arki.task.TaskDestinationOptions.build(origin, true);
        view.rows = next.rows; view.options = next.options; view.signature = next.signature;
    }

    /** 通关后继续拾取任务物品时，随已确认地图事实更新选项，不增加每帧 RPC。 */
    public static function onMapProjection():Void {
        if (!current(_view) || _view.status != "ready") return;
        var next:Object = {};
        buildRows(next);
        if (next.signature == _view.signature) return;
        _seq++;
        _view.rows = next.rows; _view.options = next.options; _view.signature = next.signature;
        _view.token = "return.options." + _seq + "." + getTimer();
        StageRunSession.notifyReturnOptionsChanged();
    }
    public static function retry():Object {
        if (!available() || isBusy()) return {success:false, error:"return_selection_unavailable"};
        reset(); StageRunSession.notifyReturnOptionsChanged();
        return {success:true, error:""};
    }
    public static function confirm(token:String, choiceId:String):Object {
        var view:Object = _view;
        if (!current(view) || view.status != "ready" || token !== view.token
                || _root._webPanelPauseLease != undefined)
            return {success:false, error:"return_selection_stale"};
        var intent:Object = view.options["$" + choiceId];
        if (intent == undefined || !complete(String(intent.taskId))) {
            retry(); return {success:false, error:"return_selection_stale"};
        }
        view.status = "confirming";
        StageRunSession.notifyReturnOptionsChanged();
        MapDomainBridge.resolveReturnPlan(intent, function(ok:Boolean, error:String, plan:Object):Void {
            org.flashNight.arki.scene.StageReturnOptions.planReady(view, intent, ok, error, plan);
        }, function():Boolean {
            return org.flashNight.arki.scene.StageReturnOptions.validFlight(view);
        });
        return {success:true, error:""};
    }
    private static function validFlight(view:Object):Boolean {
        return current(view) && view.status == "confirming" && _root._webPanelPauseLease == undefined;
    }
    private static function planReady(view:Object, intent:Object, ok:Boolean, error:String, plan:Object):Void {
        if (!current(view)) return;
        if (!ok || !validFlight(view) || !complete(String(intent.taskId))) {
            view.status = "error"; view.rows = []; view.options = {};
            StageRunSession.notifyReturnOptionsChanged();
            if (typeof _root.发布消息 == "function") _root.发布消息("交付地点已变化，请刷新目的地或返回原处。");
            return;
        }
        view.status = "ready";
        StageReturnFlow.select(plan);
        // 此处已完成 fresh 求解，接着同步进入正规返回；没有 Web 关闭或第二次导航。
        var result:Object = StageRunSession.requestReturnBaseLocal("stage_return_dropdown");
        if (result.success !== true && typeof _root.发布消息 == "function")
            _root.发布消息("返回未开始，请重试返回。（" + String(result.error) + "）");
    }
}
