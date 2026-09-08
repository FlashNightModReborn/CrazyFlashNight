/**
 * 地图命令薄适配：C# 拥有规则与选址，AS2 只执行新鲜准入后的场景跳转。
 */
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.ui.PanelRequestEnvelope;

class org.flashNight.arki.map.MapPanelService {
    private static var _json:LiteJSON;
    private static var _inited:Boolean = false;
    private static var _returnSequence:Number = 0;
    private static var _returnContext:Object;
    private static var _returnReply:Object;
    private static var _acceptedReturnToken:String = "";

    public static function install():Void {
        if (_inited) return;
        _json = new LiteJSON();
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["mapPanelSnapshot"] = function(params) { org.flashNight.arki.map.MapPanelService.handleSnapshot(params); };
        _root.gameCommands["mapPanelNavigate"] = function(params) { org.flashNight.arki.map.MapPanelService.handleNavigate(params); };
        _root.gameCommands["mapPanelReturnBase"] = function(params) { org.flashNight.arki.map.MapPanelService.handleReturnBase(params); };
        _root.gameCommands["mapPanelClose"] = function(params) { org.flashNight.arki.map.MapPanelService.handleClose(params); };
        _root.gameCommands["openWebMap"] = function(params) { org.flashNight.arki.map.MapPanelService.handleOpenWebMap(params); };
        _root.gameCommands["navigateToHotspot"] = function(params) { org.flashNight.arki.map.MapPanelService.navigateToHotspot(String(params.targetId)); };
        _inited = true;
    }

    /** 仅供展示；执行不得把这个缓存布尔值当准入凭证。 */
    public static function canNavigateToHotspot(hotspotId:String):Boolean {
        return org.flashNight.arki.scene.StageRunSession.canNavigateAwayFromStage()
            && canRouteToHotspotAfterReturn(hotspotId);
    }
    public static function canRouteToHotspotAfterReturn(hotspotId:String):Boolean {
        return MapDomainBridge.getProjection().snapshot.hotspotStates[hotspotId].enabled === true;
    }
    public static function resolveDeliverableState():Object {
        var state:Object = MapDomainBridge.getProjection().delivery;
        return state == undefined ? {hotspotId:"", navigable:false, returnNavigable:false} : state;
    }
    public static function publishDeliveryHint():Void {
        var projection:Object = MapDomainBridge.getProjection();
        var state:Object = resolveDeliverableState();
        org.flashNight.arki.render.FrameBroadcaster.pushUiState(
            "td:" + (projection.hasDeliverable === true ? "1" : "0") + "|tdh:" + String(state.hotspotId)
                + "|tdn:" + (state.navigable === true ? "1" : "0") + "|tdr:" + (state.returnNavigable === true ? "1" : "0"));
    }
    /** Boolean 仅表示已受理请求；真正执行结果通过 callback，所有调用方不得据此提前关闭。 */
    public static function navigateToHotspot(hotspotId:String, callback:Function, guard:Function):Boolean {
        if (callback == undefined) callback = function(ok:Boolean, error:String):Void {
            if (!ok) org.flashNight.arki.map.MapPanelService.navigationWarning(error);
        };
        MapDomainBridge.navigate({kind:"navigate", targetId:hotspotId}, callback, guard);
        return true;
    }
    public static function navigateToDeliverable(callback:Function, guard:Function):Void {
        MapDomainBridge.navigate({kind:"deliverable"}, callback, guard);
    }
    public static function navigateToTask(taskId:String, callback:Function, guard:Function):Void {
        MapDomainBridge.navigate({kind:"task_finish", taskId:taskId}, callback, guard);
    }
    public static function navigationWarning(error:String):Void {
        log("导航未执行：" + error);
        _root.发布消息("地图状态已变化或当前不能离开，请刷新后重试。");
    }
    // 用工厂形参保存请求编号；CS6 会把普通局部变量放进寄存器，异步回调按变量名读取时会丢失。
    private static function makeResponse(responseCallId:Number, navigation:Boolean):Function {
        return function(ok:Boolean, error:String):Void {
            var response:Object = {task:"map_response", callId:responseCallId, success:ok, error:error};
            if (navigation) response.closePanel = ok;
            else {
                response.snapshot = ok ? org.flashNight.arki.map.MapDomainBridge.getProjection().snapshot : null;
                // 退场资格归 AS2，不写进 C# 地图规则/作者预览的缓存事实。
                // 地图域读取失败也回传本轮资格，允许救援与超时后的只读核对。
                response.returnBase = org.flashNight.arki.map.MapPanelService.getReturnBaseState();
            }
            org.flashNight.arki.map.MapPanelService.sendResponse(response);
        };
    }
    public static function handleSnapshot(params:Object):Void {
        MapDomainBridge.snapshot(makeResponse(Number(params.callId), false));
    }
    public static function handleNavigate(params:Object):Void {
        MapDomainBridge.navigate({kind:"navigate", targetId:String(params.targetId)}, makeResponse(Number(params.callId), true));
    }
    public static function getReturnBaseState():Object {
        var state:Object = org.flashNight.arki.scene.StageRunSession.getMapReturnBaseState();
        if (_returnContext == null || _returnContext.world !== _root.gameworld
                || _returnContext.runId !== state.runId || _returnContext.revision !== state.revision
                || _returnContext.mode !== state.mode || _returnContext.available !== state.available) {
            _returnContext = {world:_root.gameworld, runId:state.runId, revision:state.revision,
                mode:state.mode, available:state.available, token:"map-return-" + (++_returnSequence)};
        }
        state.token = _returnContext.token;
        state.acceptedToken = _acceptedReturnToken;
        return state;
    }
    /** 只接收本面板读到的短期资格，禁止 Web 携带目的地或改写关卡结果。 */
    public static function handleReturnBase(params:Object):Void {
        var callId:Number = Number(params.callId);
        if (isNaN(callId) || callId <= 0 || Math.floor(callId) != callId) return;
        var error:String = "";
        for (var key:String in params) {
            if (key != "task" && key != "action" && key != "callId" && key != "v" && key != "token") error = "invalid_payload";
        }
        if (params.v !== 1 || typeof params.token != "string" || params.token == "") error = "invalid_payload";
        if (_returnReply != null) error = "return_in_progress";
        if (error == "" && params.token === _acceptedReturnToken) {
            sendResponse({task:"map_response", callId:callId, success:true, closePanel:true});
            return;
        }
        var state:Object = getReturnBaseState();
        if (error == "" && params.token !== state.token) error = "map_return_stale";
        if (error == "" && state.available !== true) error = "return_base_unavailable";
        if (error != "") {
            sendResponse({task:"map_response", callId:callId, success:false, error:error, returnBase:state});
            return;
        }
        // 完整回包在淡出前存入 class；不能在切帧后依赖调用帧的局部变量。
        _returnReply = {task:"map_response", callId:callId, success:true, closePanel:true, token:params.token};
        try {
            if (_root.返回基地() === false) failReturnBase(
                org.flashNight.arki.scene.StageRunSession.getReturnFailureReason() || "return_base_failed");
        } catch (returnError) {
            failReturnBase("return_base_failed");
        }
        if (_returnReply.success === true) _acceptedReturnToken = String(_returnReply.token);
        delete _returnReply.token;
        _returnReply.returnBase = getReturnBaseState();
        sendPendingReturnBaseResponse();
    }
    private static function sendPendingReturnBaseResponse():Void {
        var response:Object = _returnReply;
        _returnReply = null;
        sendResponse(response);
    }
    private static function failReturnBase(error:String):Void {
        _returnReply.success = false;
        _returnReply.error = error;
        delete _returnReply.closePanel;
    }
    public static function handleClose(params:Object):Void { _returnContext = null; log("mapPanelClose"); }
    public static function handleOpenWebMap(params:Object):Void {
        var source:String = params.source == undefined ? "as2_legacy_button" : String(params.source);
        var pageId:String = String(params.pageId || "");
        if (_root.server.sendSocketMessage == undefined) return;
        var fields:Array = pageId == "" ? [] : [{name:"pageId", value:pageId}];
        _root.server.sendSocketMessage(PanelRequestEnvelope.build("map", source, fields, []));
    }
    private static function log(msg:String):Void { _root.server.sendServerMessage("[MapWV] " + msg); }
    private static function sendResponse(resp:Object):Void { _root.server.sendSocketMessage(_json.stringifySafe(resp)); }
}
