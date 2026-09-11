/**
 * 有界地图桥的执行新鲜度与真实 NPC 适配 focused 测试；不连接运行中的游戏。
 */
import org.flashNight.arki.map.MapDomainBridge;
import org.flashNight.arki.map.MapFactsSampler;
import org.flashNight.arki.map.MapHotspotResolver;
import org.flashNight.arki.map.MapPanelService;
import org.flashNight.arki.map.MapWorldNpcController;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.task.TaskUtil;
import org.flashNight.neur.Server.ServerManager;

class org.flashNight.arki.map.MapDomainBridgeTest {
    private static var _passed:Number;
    private static var _failed:Number;
    private static var _wire:Array;
    private static var _facts:Object;
    private static var _blocked:String;
    private static var _result:Object;
    private static var _fadeCount:Number;
    private static var _frame:String;
    private static var _panelResponses:Array;
    private static var _panelCallbacks:Array;
    private static var _acceptedTasks:Array;
    private static var _interestResults:Array;

    private static function check(ok:Boolean, label:String):Void {
        if (ok) { _passed++; trace("[PASS] " + label); }
        else { _failed++; trace("[FAIL] " + label); }
    }
    private static function snapshotFields(object:Object, fields:Array):Object {
        var result:Object = {};
        for (var i:Number = 0; i < fields.length; i++) result[fields[i]] = object[fields[i]];
        return result;
    }
    private static function restoreFields(object:Object, fields:Array, saved:Object):Void {
        for (var i:Number = 0; i < fields.length; i++) object[fields[i]] = saved[fields[i]];
    }
    private static function captureResult(ok:Boolean, error:String):Void { _result = {ok:ok, error:error}; }
    private static function start():Number {
        var bridge:Object = MapDomainBridge; bridge._navigationBusyUntil = 0; _result = {};
        MapDomainBridge.navigate({kind:"deliverable"}, captureResult);
        return _wire.length - 1;
    }
    private static function reply(index:Number, override:Object):Void {
        var request:Object = _wire[index].request;
        var result:Object = {sessionToken:request.sessionToken, contentDigest:request.contentDigest,
            sceneEpoch:request.sceneEpoch, revision:request.revision,
            projection:{snapshot:{version:4,currentHotspotId:"beta"}, currentLocationId:"beta",taskEndpoints:{},placements:{}},
            admission:{admitted:true, hotspotId:"alpha", locationId:"alpha",frame:"甲场景"}};
        for (var key:String in override) result[key] = override[key];
        _wire[index].callback({success:true,result:result});
    }
    private static function checkPanelResponses():Void {
        var bridge:Object = MapDomainBridge, panel:Object = MapPanelService;
        var oldSnapshot:Function = bridge.snapshot, oldNavigate:Function = bridge.navigate;
        var oldProjection:Object = bridge._projection, oldJson:Object = panel._json, oldRootServer:Object = _root.server;
        _panelResponses = []; _panelCallbacks = [];
        try {
            bridge._projection = {snapshot:{version:4,currentHotspotId:"alpha"}}; panel._json = new LiteJSON();
            bridge.snapshot = function(callback:Function):Void { org.flashNight.arki.map.MapDomainBridgeTest._panelCallbacks.push(callback); };
            bridge.navigate = function(intent:Object, callback:Function):Void { org.flashNight.arki.map.MapDomainBridgeTest._panelCallbacks.push(callback); };
            _root.server = {sendSocketMessage:function(wire:String):Void {
                org.flashNight.arki.map.MapDomainBridgeTest._panelResponses.push((new JSON(false)).parse(wire));
                trace("MapPanelServiceTest wire: " + wire);
            }};
            var first:Object = {callId:71};
            MapPanelService.handleSnapshot(first); MapPanelService.handleSnapshot({callId:72}); first.callId = 999;
            check(_panelResponses.length == 0 && _panelCallbacks.length == 2, "panel snapshot waits for its asynchronous result");
            _panelCallbacks[1](true, ""); _panelCallbacks[0](true, "");
            check(_panelResponses[0].callId === 72 && _panelResponses[1].callId === 71,
                "out-of-order snapshot callbacks preserve separate numeric callIds after the caller returns");
            check(_panelResponses[0].task == "map_response" && _panelResponses[0].snapshot.version === 4,
                "snapshot wire contains the production response envelope");
            MapPanelService.handleSnapshot({callId:73}); _panelCallbacks[2](false, "map_facts_stale");
            check(_panelResponses[2].callId === 73 && _panelResponses[2].success === false
                && _panelResponses[2].snapshot === null && _panelResponses[2].error == "map_facts_stale", "snapshot failure retains its original callId");
            MapPanelService.handleNavigate({callId:74,targetId:"alpha"}); MapPanelService.handleNavigate({callId:75,targetId:"beta"});
            _panelCallbacks[4](false, "not_navigable"); _panelCallbacks[3](true, "");
            check(_panelResponses[3].callId === 75 && _panelResponses[3].closePanel === false
                && _panelResponses[3].error == "not_navigable", "rejected navigation keeps its callId and does not close the panel");
            check(_panelResponses[4].callId === 74 && _panelResponses[4].success === true && _panelResponses[4].closePanel === true,
                "successful navigation keeps its callId and exact close result");
            MapPanelService.handleSnapshot({callId:2147483647}); _panelCallbacks[5](true, "");
            check(_panelResponses[5].callId === 2147483647, "panel wire preserves the maximum positive Host callId without string coercion");
        } finally {
            bridge.snapshot = oldSnapshot; bridge.navigate = oldNavigate; bridge._projection = oldProjection;
            panel._json = oldJson; _root.server = oldRootServer;
        }
    }
    private static function checkMapReturn():Void {
        var stage:Object = StageRunSession, panel:Object = MapPanelService;
        var stageFields:Array = ["_run", "_returnRequested", "_stageStartReservation"];
        var panelFields:Array = ["_returnContext", "_returnReply", "_acceptedReturnToken", "_returnSequence", "_json"];
        var rootFields:Array = ["gameworld", "当前为战斗地图", "场景转换中", "返回基地", "server", "__mapReturnCalls", "__mapReturnFailure"];
        var savedStage:Object = snapshotFields(stage, stageFields);
        var savedPanel:Object = snapshotFields(panel, panelFields);
        var savedRoot:Object = snapshotFields(_root, rootFields);
        try {
            _blocked = "";
            _panelResponses = [];
            panel._json = new LiteJSON(); panel._returnContext = null; panel._returnReply = null; panel._acceptedReturnToken = "";
            panel._returnSequence = 0;
            _root.server = {sendSocketMessage:function(json:String):Void {
                org.flashNight.arki.map.MapDomainBridgeTest._panelResponses.push(new LiteJSON().parse(json));
            }};
            _root.gameworld = {identity:"first"}; _root.当前为战斗地图 = true; _root.场景转换中 = false;
            _root.__mapReturnCalls = 0; _root.__mapReturnFailure = "";
            _root.返回基地 = function():Boolean {
                _root.__mapReturnCalls++;
                if (_root.__mapReturnFailure == "throw") throw new Error("test fade failure");
                if (_root.__mapReturnFailure == "reject") return false;
                return true;
            };
            stage._run = {runId:"map-run-1", revision:1, life:"alive", outcome:"active", settlement:"none"};
            stage._returnRequested = false; stage._stageStartReservation = null;
            var state:Object = MapPanelService.getReturnBaseState();
            check(state.available === true && state.mode == "retreat", "alive combat exposes explicit retreat capability");
            check(StageRunSession.requestReturnBaseLocal("hud").success === false && _root.__mapReturnCalls == 0,
                "normal HUD return keeps its alive-combat restriction");
            check(MapPanelService.getReturnBaseState().token === state.token, "unchanged return capability keeps its short-lived token");
            stage._stageStartReservation = {token:"start"};
            check(!StageRunSession.getMapReturnBaseState().available && StageRunSession.getMapReturnBaseState().mode == "entering",
                "entry reservation never exposes retreat");
            stage._stageStartReservation = null;
            stage._run.outcome = "victory";
            check(StageRunSession.getMapReturnBaseState().mode == "victory", "victory projects return and settlement instead of retreat");
            stage._run.life = "dead";
            check(StageRunSession.getMapReturnBaseState().mode == "return", "dead actor retains canonical medical return routing");
            stage._run.life = "alive"; stage._run.outcome = "active";
            state = MapPanelService.getReturnBaseState();
            MapPanelService.handleReturnBase({v:1,callId:81,token:state.token,targetId:"other"});
            var response:Object = _panelResponses.pop();
            check(response.error == "invalid_payload" && _root.__mapReturnCalls == 0, "return rejects a supplied destination before authority effects");
            stage._run.revision++;
            MapPanelService.handleReturnBase({v:1,callId:82,token:state.token}); response = _panelResponses.pop();
            check(response.error == "map_return_stale" && _root.__mapReturnCalls == 0, "changed run revision rejects the previous return token");
            state = MapPanelService.getReturnBaseState();
            _root.gameworld = {identity:"replacement"};
            MapPanelService.handleReturnBase({v:1,callId:83,token:state.token}); response = _panelResponses.pop();
            check(response.error == "map_return_stale" && _root.__mapReturnCalls == 0, "world replacement invalidates the return token");
            state = MapPanelService.getReturnBaseState();
            _root.__mapReturnFailure = "reject";
            MapPanelService.handleReturnBase({v:1,callId:84,token:state.token}); response = _panelResponses.pop();
            check(!response.success && response.closePanel !== true && response.error == "return_base_failed",
                "failed settlement or flush does not close the map");
            check(response.returnBase.acceptedToken != state.token && response.returnBase.available,
                "rejected return remains retryable and is never an accepted receipt");
            _root.__mapReturnFailure = "throw";
            MapPanelService.handleReturnBase({v:1,callId:85,token:state.token}); response = _panelResponses.pop();
            check(response.error == "return_base_failed" && response.closePanel !== true, "throwing transition preserves the map and retry right");
            _root.__mapReturnFailure = "";
            MapPanelService.handleReturnBase({v:1,callId:2147483647,token:state.token}); response = _panelResponses.pop();
            check(response.success && response.closePanel && response.callId === 2147483647,
                "accepted return retains exact numeric correlation and confirmed close");
            check(MapPanelService.getReturnBaseState().acceptedToken === state.token,
                "fresh read can prove acceptance after a lost return response");
            var calls:Number = _root.__mapReturnCalls;
            MapPanelService.handleReturnBase({v:1,callId:86,token:state.token}); response = _panelResponses.pop();
            check(response.success && _root.__mapReturnCalls == calls, "duplicate accepted return cannot repeat a scene transition");
            stage._returnRequested = true; stage._run.settlement = "prepared"; _root.当前为战斗地图 = false;
            check(!StageRunSession.getMapReturnBaseState().available && StageRunSession.getMapReturnBaseState().mode == "settlement_pending",
                "pending settlement cannot expose another escape");
            _root.当前为战斗地图 = true;
            check(StageRunSession.getMapReturnBaseState().available && StageRunSession.getMapReturnBaseState().mode == "retry_return",
                "frozen return with a failed fade remains retryable");
            _root.场景转换中 = true;
            check(!StageRunSession.getMapReturnBaseState().available, "in-progress transition hides escape");
            _root.场景转换中 = false; stage._run = null; stage._returnRequested = false;
            check(StageRunSession.getMapReturnBaseState().available, "legacy battle without a run can use canonical rescue");
            _root.当前为战斗地图 = false;
            check(!StageRunSession.getMapReturnBaseState().available, "base scene offers no redundant rescue");
        } finally {
            restoreFields(stage, stageFields, savedStage); restoreFields(panel, panelFields, savedPanel); restoreFields(_root, rootFields, savedRoot);
        }
    }
    private static function interestIds(count:Number, start:Number):Array {
        var result:Array = [];
        for (var i:Number = 0; i < count; i++) result.push(String(start + i));
        return result;
    }
    private static function captureInterestResult(ok:Boolean, error:String):Void {
        _interestResults.push({ok:ok,error:error});
    }
    private static function replyInterests(index:Number):Void {
        var endpoints:Object = {}, autoAccept:Object = {};
        var ids:Array = _wire[index].request.interestTaskIds;
        for (var i:Number = 0; i < ids.length; i++) {
            endpoints[ids[i]] = {};
            autoAccept[ids[i]] = {allowed:true,nextTaskId:String(Number(ids[i]) + 1)};
        }
        reply(index, {projection:{snapshot:{version:4},taskEndpoints:endpoints,
            autoAccept:autoAccept,placements:{}}});
    }
    private static function checkInterestLifetimes():Void {
        var bridge:Object = MapDomainBridge, sampler:Object = MapFactsSampler;
        var world:Object = MapWorldNpcController, server:Object = ServerManager.getInstance();
        var oldObserve:Function = bridge.observeScene, oldRefresh:Function = world.refresh;
        var oldCapture:Function = sampler.capture, oldTasks:Object = TaskUtil.tasks;
        var oldConnected:Boolean = server.isSocketConnected;
        var rootFields:Array = ["taskAvailable", "GetTask"];
        var savedRoot:Object = snapshotFields(_root, rootFields);
        try {
            bridge.observeScene = function():Void {};
            world.refresh = function():Void {};
            bridge._installed = true; server.isSocketConnected = true;
            bridge._bootstrap = {frames:{alpha:"甲场景"},worldBindings:[]};
            bridge._sessionToken = "interest-session"; bridge._loadedDigest = "interest-content";
            bridge._flight = undefined; bridge._navigationFlight = undefined;
            bridge._waiters = []; bridge._knownTasks = {}; bridge._interests = [];
            _acceptedTasks = []; _interestResults = []; TaskUtil.tasks = {};
            for (var i:Number = 0; i < 301; i++) {
                bridge._knownTasks["$" + i] = true;
                TaskUtil.tasks[String(i)] = {id:String(i)};
            }
            sampler.capture = function(bootstrap:Object, ids:Array):Object {
                var available:Object = {};
                for (var i:Number = 0; i < ids.length; i++) available[String(ids[i])] = true;
                return {ready:true,facts:{base:org.flashNight.arki.map.MapDomainBridgeTest._facts,available:available}};
            };
            _root.taskAvailable = function(id:String):Boolean { return true; };
            _root.GetTask = function(id:String):Void { org.flashNight.arki.map.MapDomainBridgeTest._acceptedTasks.push(id); };

            // 原事故反例：历史关注满额，已完成任务不在 activeOrder 补齐集合中。
            bridge._interests = interestIds(128, 0);
            TaskUtil.requestAutoAcceptAfterFinish("200");
            var first:Number = _wire.length - 1;
            check(_wire[first].request.interestTaskIds.length <= 128
                && _wire[first].request.interestTaskIds.join(",").indexOf("200") >= 0,
                "completed task interest survives a full historical list");
            replyInterests(first);
            check(_acceptedTasks.length == 1 && _acceptedTasks[0] == "201",
                "real auto-accept callback advances the chain after interest saturation");
            replyInterests(first);
            check(_acceptedTasks.length == 1, "duplicate completed projection cannot accept the next task twice");

            // 长会话超过单包容量；每次只保留当前需要的任务事实。
            _acceptedTasks = [];
            for (i = 0; i < 130; i++) {
                TaskUtil.requestAutoAcceptAfterFinish(String(i));
                replyInterests(_wire.length - 1);
            }
            check(_acceptedTasks.length == 130 && _acceptedTasks[129] == "130",
                "130 sequential task completions keep auto-accept working");

            // 并发超过容量须分批；新增需求不得改变在途请求的采样签名。
            _interestResults = [];
            var ids:Array = interestIds(128, 0);
            MapDomainBridge.snapshot(captureInterestResult, ids);
            first = _wire.length - 1; ids[0] = "299";
            MapDomainBridge.snapshot(captureInterestResult, ["200"]);
            check(_wire.length - 1 == first && _wire[first].request.interestTaskIds[0] == "0",
                "snapshot clones caller ids and preserves its in-flight request");
            replyInterests(first);
            check(_interestResults.length == 1 && _interestResults[0].ok === true,
                "later interest demand does not invalidate the first projection signature");
            MapDomainBridge.tick();
            check(_wire.length - 1 > first && _wire[_wire.length - 1].request.interestTaskIds.length <= 128,
                "overflow snapshot demand is dispatched in a bounded second batch");
            replyInterests(_wire.length - 1);
            check(_interestResults.length == 2 && _interestResults[1].ok === true,
                "overflow waiter completes instead of silently timing out");

            // 工作台两个采样各需 128 个不同编号，不得把其中一份 receipt 配到半份事实。
            MapDomainBridge.snapshot(captureInterestResult);
            first = _wire.length - 1;
            var captureA:String = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", captureB:String = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
            ids = interestIds(128, 0);
            bridge.collect({sessionToken:bridge._sessionToken,contentDigest:bridge._loadedDigest,captureId:captureA,interestTaskIds:ids});
            ids[0] = "299";
            bridge.collect({sessionToken:bridge._sessionToken,contentDigest:bridge._loadedDigest,captureId:captureB,interestTaskIds:interestIds(128,128)});
            replyInterests(first); MapDomainBridge.tick();
            var batch:Object = _wire[_wire.length - 1].request;
            check(batch.captureIds.length == 1 && batch.captureIds[0] == captureA
                && batch.interestTaskIds.length == 128 && batch.interestTaskIds[0] == "0",
                "first capture keeps its complete immutable interest set and only its own receipt");
            replyInterests(_wire.length - 1); MapDomainBridge.tick();
            batch = _wire[_wire.length - 1].request;
            check(batch.captureIds.length == 1 && batch.captureIds[0] == captureB
                && batch.interestTaskIds.length == 128 && batch.interestTaskIds[0] == "128",
                "second capture is deferred with all its interests instead of truncated");
            replyInterests(_wire.length - 1);

            var before:Number = _acceptedTasks.length;
            TaskUtil.requestAutoAcceptAfterFinish("200");
            first = _wire.length - 1; bridge._sceneEpoch++;
            replyInterests(first);
            check(_acceptedTasks.length == before, "scene change prevents late automatic task acceptance");
            TaskUtil.requestAutoAcceptAfterFinish("200");
            first = _wire.length - 1; bridge._waiters[0].deadline = -1;
            replyInterests(first);
            check(_acceptedTasks.length == before && bridge._waiters.length == 0,
                "expired automatic task acceptance releases demand and ignores a late success");

            _interestResults = []; before = _wire.length;
            MapDomainBridge.snapshot(captureInterestResult, ["unknown"]);
            MapDomainBridge.snapshot(captureInterestResult, interestIds(129,0));
            check(_wire.length == before && _interestResults.length == 2
                && _interestResults[0].ok === false && _interestResults[1].ok === false,
                "unknown or individually oversized interests reject explicitly without a pending waiter");
        } finally {
            bridge._installed = false; bridge._waiters = []; bridge._flight = undefined;
            bridge.observeScene = oldObserve; world.refresh = oldRefresh; sampler.capture = oldCapture;
            server.isSocketConnected = oldConnected; TaskUtil.tasks = oldTasks;
            restoreFields(_root,rootFields,savedRoot);
        }
    }
    public static function runAllTests():Void {
        _passed = 0; _failed = 0; _wire = []; _facts = {chains:{主线:0},tasks:{},scene:{stageFlag:"甲场景"}}; _blocked = "";
        _fadeCount = 0; _frame = "";
        trace("=== MapDomainBridgeTest start ===");
        var bridge:Object = MapDomainBridge, sampler:Object = MapFactsSampler, stage:Object = StageRunSession;
        var panel:Object = MapPanelService, resolver:Object = MapHotspotResolver, world:Object = MapWorldNpcController;
        var server:Object = ServerManager.getInstance();
        var fields:Array = ["_installed","_bootstrap","_projection","_json","_loadedDigest","_sessionToken","_helloFlight","_flight",
            "_navigationFlight","_waiters","_interests","_knownTasks","_revision","_acceptedRevision","_sceneEpoch",
            "_lastWorld","_sceneStamp","_signature","_confirmedSignature","_lastAttempt","_helloAttempt","_navigationBusyUntil","_force"];
        var saved:Object = snapshotFields(bridge,fields);
        var rootFields:Array = ["淡出动画","关卡结束界面","场景进入位置名","__pushMapHudState","gameworld","初始化NPC"];
        var rootSaved:Object = snapshotFields(_root,rootFields);
        var worldFields:Array = ["_entries","_permit","_permitPresence"];
        var worldSaved:Object = snapshotFields(world,worldFields);
        var oldCapture:Function = sampler.capture, oldBlock:Function = stage.getSceneExitBlockReason;
        var oldSend:Function = server.sendTaskWithCallback, oldHint:Function = panel.publishDeliveryHint, oldPending:Function = resolver.beginPending;
        try {
            bridge._installed = false; bridge._json = new LiteJSON(); bridge._bootstrap = {frames:{alpha:"甲场景",beta:"乙场景"},
                locationByHotspot:{alpha:"alpha",beta:"beta"},worldBindings:[]}; bridge._projection = undefined;
            bridge._loadedDigest = "content-a"; bridge._sessionToken = "session-a"; bridge._sceneEpoch = 1;
            bridge._revision = 0; bridge._acceptedRevision = -1; bridge._signature = ""; bridge._confirmedSignature = "";
            bridge._navigationFlight = undefined; bridge._flight = undefined; bridge._waiters = []; bridge._interests = [];
            bridge._knownTasks = {};
            sampler.capture = function():Object { return {ready:true,facts:org.flashNight.arki.map.MapDomainBridgeTest._facts}; };
            stage.getSceneExitBlockReason = function():String { return org.flashNight.arki.map.MapDomainBridgeTest._blocked; };
            server.sendTaskWithCallback = function(kind:String, request:Object, third:Object, callback:Function):Void {
                org.flashNight.arki.map.MapDomainBridgeTest._wire.push({request:request,callback:callback});
            };
            panel.publishDeliveryHint = function():Void {};
            resolver.beginPending = function():Void {};
            _root.__pushMapHudState = function():Void {};
            _root.关卡结束界面 = {_visible:1};
            _root.淡出动画 = {淡出跳转帧:function(frame:String):Void {
                org.flashNight.arki.map.MapDomainBridgeTest._fadeCount++;
                org.flashNight.arki.map.MapDomainBridgeTest._frame = frame;
            }};

            var oldB:Number = start();
            _facts = {chains:{主线:1},tasks:{},scene:{stageFlag:"甲场景"}};
            reply(oldB, {admission:{admitted:true,hotspotId:"beta",locationId:"beta",frame:"乙场景"}});
            check(_result.ok === false && _fadeCount == 0, "reward changed facts rejects the old B admission");
            var freshA:Number = start(); reply(freshA, {});
            check(_result.ok === true && _fadeCount == 1 && _frame == "甲场景", "fresh A executes exactly once");
            reply(oldB, {}); check(_fadeCount == 1, "late duplicate B cannot override A");

            var scene:Number = start(); bridge._sceneEpoch++; reply(scene,{});
            check(_result.ok === false && _fadeCount == 1, "scene epoch change rejects an in-flight result");
            var session:Number = start(); bridge._sessionToken = "session-b"; reply(session,{});
            check(_result.ok === false, "session change rejects an in-flight result");
            var content:Number = start(); reply(content,{contentDigest:"other-content"});
            check(_result.ok === false, "content mismatch rejects execution");
            var lifecycle:Number = start(); _blocked = "combat_active"; reply(lifecycle,{});
            check(_result.ok === false && _fadeCount == 1, "late lifecycle lock is checked before fade");
            var count:Number = _wire.length; start();
            check(_result.ok === false && _wire.length == count, "active lifecycle stops even submitting a navigation RPC");
            _blocked = ""; var badFrame:Number = start();
            reply(badFrame,{admission:{admitted:true,hotspotId:"alpha",locationId:"alpha",frame:"伪造帧"}});
            check(_result.ok === false && _fadeCount == 1, "host admission must match the frozen physical route");
            bridge._navigationBusyUntil = 0;
            MapDomainBridge.navigate({kind:"navigate",targetId:"alpha"},captureResult,function():Boolean { return false; });
            reply(_wire.length-1,{}); check(_result.ok === false, "caller exact-operation guard runs before execution");

            var sameLocation:Number = start();
            reply(sameLocation, {projection:{snapshot:{version:4,currentHotspotId:"alpha"}, currentLocationId:"alpha", taskEndpoints:{}, placements:{}}});
            check(_result.ok === true && _fadeCount == 1, "same-location ordinary navigation succeeds without another fade");

            var firstWaiter:Number = 0, secondWaiter:Number = 0;
            bridge._waiters = [{sceneEpoch:bridge._sceneEpoch,ids:[],callback:function():Void {
                firstWaiter++; MapDomainBridge.snapshot(function():Void { secondWaiter++; });
            }}];
            bridge.sendProjection(bridge.context()); reply(_wire.length-1,{});
            check(firstWaiter == 1 && secondWaiter == 0 && bridge._waiters.length == 1, "reentrant fresh waiter is retained, not overwritten by the completing batch");
            bridge.sendProjection(bridge.context()); reply(_wire.length-1,{});
            check(secondWaiter == 1 && bridge._waiters.length == 0, "new waiter consumes its own fresh projection");

            world._entries = []; world._permit = undefined; world._permitPresence = false;
            _root.gameworld = {};
            var initialized:Number = 0, managedPermit:Boolean = false;
            _root.初始化NPC = function(npc:Object):Void { initialized++; managedPermit = MapWorldNpcController.hasPresencePermit(npc); npc.NPC初始化完毕 = true; };
            bridge._bootstrap.worldBindings = [{placementId:"place",locationId:"alpha",runtimeName:"甲",taskName:"甲",instanceName:"npc",ready:true}];
            var npc:Object = {_parent:_root.gameworld,_name:"npc",名字:"甲"};
            bridge._projection = {currentLocationId:"",placements:{place:{present:true,worldReady:true}}};
            check(MapWorldNpcController.intercept(npc), "explicit world identity is intercepted");
            MapWorldNpcController.refresh();
            check(npc._visible === false && initialized == 0, "unknown location cannot fall back to legacy initialization");
            bridge._projection.currentLocationId = "alpha"; MapWorldNpcController.refresh();
            check(npc._visible === true && initialized == 1 && managedPermit, "present bound NPC initializes with the scoped presence permit");
            MapWorldNpcController.refresh(); check(initialized == 1, "bound NPC initialization is exactly once");
            bridge._projection.placements.place.present = false; MapWorldNpcController.refresh();
            check(npc._visible === false && !MapWorldNpcController.canInteract(npc), "absent bound NPC is hidden and cannot interact");
            bridge._projection.placements.place.present = true; bridge._projection.placements.place.worldReady = false; MapWorldNpcController.refresh();
            check(npc._visible === false, "unready published source stays fail closed");
            var elsewhere:Object = {_parent:_root.gameworld,_name:"npc",名字:"甲"};
            bridge._projection.currentLocationId = "beta"; MapWorldNpcController.intercept(elsewhere); MapWorldNpcController.refresh();
            check(initialized == 2 && !managedPermit, "same name at an unbound location keeps legacy initialization");
            checkPanelResponses();
            checkMapReturn();
            checkInterestLifetimes();
        } catch(error) { _failed++; trace("[FAIL] unexpected bridge test exception: " + error); }
        finally {
            restoreFields(bridge,fields,saved); restoreFields(world,worldFields,worldSaved); restoreFields(_root,rootFields,rootSaved);
            sampler.capture = oldCapture; stage.getSceneExitBlockReason = oldBlock; server.sendTaskWithCallback = oldSend;
            panel.publishDeliveryHint = oldHint; resolver.beginPending = oldPending;
        }
        trace("MapDomainBridgeTest Tests Passed: " + _passed);
        trace("MapDomainBridgeTest Tests Failed: " + _failed);
        trace("=== MapDomainBridgeTest end ===");
    }
}
