/**
 * C# 地图域的有界事实桥。同步 getter 只读已确认投影；准入意图必须 fresh RPC + 执行前同帧复验。
 */
import org.flashNight.neur.Server.ServerManager;

class org.flashNight.arki.map.MapDomainBridge {
    private static var _installed:Boolean = false;
    private static var _bootstrap:Object;
    private static var _projection:Object;
    private static var _json:LiteJSON;
    private static var _loadedDigest:String = "";
    private static var _sessionToken:String = "";
    private static var _helloFlight:Boolean = false;
    private static var _flight:Object;
    private static var _navigationFlight:Object;
    private static var _waiters:Array;
    private static var _interests:Array;
    private static var _captureIds:Array;
    private static var _knownTasks:Object;
    private static var _revision:Number = 0;
    private static var _acceptedRevision:Number = -1;
    private static var _sceneEpoch:Number = 0;
    private static var _lastWorld:Object;
    private static var _sceneStamp:String = "";
    private static var _signature:String = "";
    private static var _confirmedSignature:String = "";
    private static var _lastAttempt:Number = 0;
    private static var _helloAttempt:Number = 0;
    private static var _navigationBusyUntil:Number = 0;
    private static var _force:Boolean = false;

    public static function initialize():Void {
        if (_installed) return;
        _installed = true; _json = new LiteJSON(); _waiters = []; _interests = []; _captureIds = []; _knownTasks = {};
        _root.__boot.mapDomainReady = false;
        _root.__boot.mapDomainFailed = false;
        _root.gameCommands["mapDomainCollect"] = function(params:Object):Void {
            org.flashNight.arki.map.MapDomainBridge.collect(params);
        };
        if (_root.__mapDomainTick != undefined) _root.__mapDomainTick.removeMovieClip();
        var tick:MovieClip = _root.createEmptyMovieClip("__mapDomainTick", _root.getNextHighestDepth());
        tick.onEnterFrame = function():Void { org.flashNight.arki.map.MapDomainBridge.tick(); };
        observeScene();
        hello();
    }

    private static function log(message:String):Void {
        if (_root.server != undefined) _root.server.sendServerMessage("[MapDomain] " + message);
    }
    private static function hello():Void {
        if (_helloFlight || !ServerManager.getInstance().isSocketConnected) return;
        _helloFlight = true; _helloAttempt = getTimer();
        ServerManager.getInstance().sendTaskWithCallback("map_domain", {version:2, op:"hello"}, null, function(response:Object):Void {
            org.flashNight.arki.map.MapDomainBridge.onHello(response);
        }, 120);
    }
    private static function onHello(response:Object):Void {
        _helloFlight = false;
        var result:Object = response.result;
        if (response.success !== true || result.version !== 2 || typeof result.sessionToken != "string"
                || result.sessionToken.length != 32 || typeof result.contentDigest != "string"
                || result.contentDigest.length != 64 || !(result.taskIds instanceof Array)
                || !(result.chains instanceof Array) || !(result.worldBindings instanceof Array) || !(result.infrastructureKeys instanceof Array)
                || !(result.availableTaskIds instanceof Array) || result.taskNpcLabels == undefined
                || result.locationByHotspot == undefined || result.frames == undefined) {
            _root.__boot.mapDomainFailed = true;
            log("静态地图加载失败：" + String(response.error || "invalid_bootstrap"));
            return;
        }
        if (_loadedDigest != "" && _loadedDigest != result.contentDigest) {
            _root.__boot.mapDomainFailed = true;
            log("地图内容已变化，必须重启游戏，不混用已加载任务与新地图。");
            return;
        }
        _loadedDigest = result.contentDigest; _sessionToken = result.sessionToken; _bootstrap = result;
        _knownTasks = {};
        for (var i:Number = 0; i < result.taskIds.length; i++) _knownTasks["$" + String(result.taskIds[i])] = true;
        _projection = undefined; _confirmedSignature = ""; _acceptedRevision = -1;
        _root.__boot.mapDomainReady = true;
        _root.__boot.mapDomainFailed = false;
        _force = true;
        log("地图静态投影已安装，人物/驻点与任务端点同源。");
    }

    private static function observeScene():Void {
        if (!_installed) return;
        var scene:Object = org.flashNight.arki.map.MapFactsSampler.scene();
        var stamp:String = _json.stringifySafe(scene);
        if (_lastWorld !== _root.gameworld || stamp != _sceneStamp) {
            _lastWorld = _root.gameworld; _sceneStamp = stamp; _sceneEpoch++;
            _projection = undefined; _confirmedSignature = ""; _force = true;
        }
    }
    private static function context():Object {
        observeScene();
        var sampled:Object = org.flashNight.arki.map.MapFactsSampler.capture(_bootstrap, _interests);
        var signature:String = _json.stringifySafe({sceneEpoch:_sceneEpoch, ready:sampled.ready, facts:sampled.facts});
        if (signature != _signature) { _signature = signature; _revision++; }
        return {signature:signature, revision:_revision, sceneEpoch:_sceneEpoch, ready:sampled.ready, facts:sampled.facts,
            sessionToken:_sessionToken, contentDigest:_loadedDigest, deadline:getTimer() + 3000};
    }
    private static function payload(ctx:Object):Object {
        var interests:Array = [];
        for (var i:Number = 0; i < _interests.length; i++) interests.push(_interests[i]);
        return {version:2, op:"project", sessionToken:ctx.sessionToken, contentDigest:ctx.contentDigest,
            revision:ctx.revision, sceneEpoch:ctx.sceneEpoch, ready:ctx.ready, facts:ctx.facts,
            interestTaskIds:interests, captureIds:[], intent:null};
    }

    public static function tick():Void {
        if (!_installed) return;
        observeScene();
        if (!ServerManager.getInstance().isSocketConnected) {
            _sessionToken = ""; _bootstrap = undefined; _projection = undefined; _confirmedSignature = "";
        }
        if (_bootstrap == undefined) {
            if (getTimer() - _helloAttempt > 1000) hello();
            expireWaiters();
            org.flashNight.arki.map.MapWorldNpcController.refresh();
            return;
        }
        expireWaiters();
        if (_flight == undefined && (getTimer() - _lastAttempt > 200 || _force || _waiters.length > 0 || _captureIds.length > 0)) {
            var ctx:Object = context();
            if (ctx.ready || _captureIds.length > 0) {
                if (_force || _waiters.length > 0 || _captureIds.length > 0 || ctx.signature != _confirmedSignature) sendProjection(ctx);
                else _lastAttempt = getTimer();
            }
        }
        org.flashNight.arki.map.MapWorldNpcController.refresh();
    }
    private static function sendProjection(ctx:Object):Void {
        _flight = ctx; _force = false; _lastAttempt = getTimer();
        var request:Object = payload(ctx);
        request.captureIds = _captureIds; _captureIds = [];
        ServerManager.getInstance().sendTaskWithCallback("map_domain", request, null, function(response:Object):Void {
            org.flashNight.arki.map.MapDomainBridge.onProjection(ctx, response);
        }, 90);
    }
    private static function installResult(ctx:Object, response:Object):Boolean {
        var result:Object = response.result;
        if (response.success !== true) {
            if (response.error == "invalid_session") { _bootstrap = undefined; _sessionToken = ""; _projection = undefined; _helloAttempt = 0; }
            return false;
        }
        observeScene();
        if (getTimer() > ctx.deadline || ctx.sceneEpoch !== _sceneEpoch || ctx.sessionToken != _sessionToken
                || result.sessionToken != ctx.sessionToken || result.contentDigest != ctx.contentDigest
                || result.sceneEpoch !== ctx.sceneEpoch || result.revision !== ctx.revision
                || result.projection.snapshot.version !== 4) return false;
        var current:Object = context();
        if (current.signature != ctx.signature || ctx.revision < _acceptedRevision) return false;
        _projection = result.projection; _confirmedSignature = ctx.signature; _acceptedRevision = ctx.revision;
        return true;
    }
    private static function onProjection(ctx:Object, response:Object):Void {
        if (_flight !== ctx) return;
        _flight = undefined;
        if (!installResult(ctx, response)) { expireWaiters(); return; }
        var pending:Array = _waiters; _waiters = [];
        for (var i:Number = 0; i < pending.length; i++) {
            var waiter:Object = pending[i];
            var ready:Boolean = waiter.sceneEpoch == _sceneEpoch;
            for (var j:Number = 0; j < waiter.ids.length; j++) if (_projection.taskEndpoints[String(waiter.ids[j])] == undefined) ready = false;
            if (ready) waiter.callback(true, "");
            else _waiters.push(waiter);
        }
        if (_root.__pushMapHudState != undefined) _root.__pushMapHudState(true);
        org.flashNight.arki.map.MapPanelService.publishDeliveryHint();
    }
    private static function expireWaiters():Void {
        var pending:Array = _waiters; _waiters = [];
        for (var i:Number = 0; i < pending.length; i++) {
            var waiter:Object = pending[i];
            if (getTimer() > waiter.deadline || waiter.sceneEpoch != _sceneEpoch) waiter.callback(false, "map_facts_stale");
            else _waiters.push(waiter);
        }
    }
    private static function addInterests(ids:Array):Void {
        if (ids == undefined) return;
        for (var i:Number = 0; i < ids.length; i++) {
            var id:String = String(ids[i]);
            if (_knownTasks["$" + id] !== true) continue;
            var found:Boolean = false;
            for (var j:Number = 0; j < _interests.length; j++) if (_interests[j] == id) found = true;
            if (!found && _interests.length < 128) _interests.push(id);
        }
    }
    public static function snapshot(callback:Function, ids:Array):Void {
        observeScene();
        if (_bootstrap == undefined || _sessionToken == "") { callback(false, "map_domain_not_ready"); return; }
        addInterests(ids);
        _waiters.push({callback:callback, ids:ids == undefined ? [] : ids, sceneEpoch:_sceneEpoch, deadline:getTimer() + 3000});
        _force = true;
        tick();
    }
    private static function collect(params:Object):Void {
        if (_bootstrap == undefined || params.sessionToken != _sessionToken || params.contentDigest != _loadedDigest
                || typeof params.captureId != "string" || params.captureId.length != 32 || !(params.interestTaskIds instanceof Array)) return;
        if (_captureIds.length >= 8) return;
        addInterests(params.interestTaskIds); _captureIds.push(params.captureId); _force = true; tick();
    }

    public static function navigate(intent:Object, callback:Function, guard:Function):Void {
        observeScene();
        var lifecycleReason:String = org.flashNight.arki.scene.StageRunSession.getSceneExitBlockReason();
        if (lifecycleReason != "") { callback(false, lifecycleReason); return; }
        if (_bootstrap == undefined || _sessionToken == "") { callback(false, "map_domain_not_ready"); return; }
        if (_navigationFlight != undefined || getTimer() < _navigationBusyUntil) { callback(false, "navigation_busy"); return; }
        if (intent.kind == "task_finish") addInterests([String(intent.taskId)]);
        var ctx:Object = context();
        if (!ctx.ready) { callback(false, "game_not_ready"); return; }
        ctx.callback = callback; ctx.guard = guard; _navigationFlight = ctx;
        var request:Object = payload(ctx); request.intent = intent;
        ServerManager.getInstance().sendTaskWithCallback("map_domain", request, null, function(response:Object):Void {
            org.flashNight.arki.map.MapDomainBridge.onNavigate(ctx, response);
        }, 90);
    }
    private static function onNavigate(ctx:Object, response:Object):Void {
        if (_navigationFlight !== ctx) return;
        _navigationFlight = undefined;
        if (!installResult(ctx, response)) { ctx.callback(false, String(response.error || "map_facts_stale")); return; }
        var admission:Object = response.result.admission;
        if (admission.admitted !== true) { ctx.callback(false, String(admission.error || "not_navigable")); return; }
        if (org.flashNight.arki.scene.StageRunSession.getSceneExitBlockReason() != ""
                || (ctx.guard != undefined && ctx.guard() !== true)
                || _bootstrap.frames[String(admission.locationId)] !== admission.frame
                || typeof _root.淡出动画.淡出跳转帧 != "function") {
            ctx.callback(false, "not_navigable"); return;
        }
        _navigationBusyUntil = getTimer() + 1500;
        org.flashNight.arki.map.MapHotspotResolver.beginPending(String(admission.hotspotId));
        _root.关卡结束界面._visible = 0;
        _root.场景进入位置名 = "出生地";
        _root.淡出动画.淡出跳转帧(String(admission.frame));
        ctx.callback(true, "");
    }

    public static function invalidate():Void { _force = true; }
    public static function getProjection():Object {
        observeScene();
        return _bootstrap == undefined || _sessionToken == "" ? undefined : _projection;
    }
    public static function getBootstrap():Object { return _bootstrap; }
    public static function getProjectionToken():String { return getProjection() == undefined ? "" : _sessionToken + "." + _acceptedRevision; }
    public static function getSceneEpoch():Number { observeScene(); return _sceneEpoch; }
    public static function locationForHotspot(id:String):String { return String(_bootstrap.locationByHotspot[id] || ""); }
    public static function pageForHotspot(id:String):String { return String(_bootstrap.pageByHotspot[id] || ""); }
    public static function endpoint(taskId:String, role:String):Object { return getProjection().taskEndpoints[taskId][role]; }
    public static function taskNpcLabel(taskId:String, role:String):String { return String(_bootstrap.taskNpcLabels[taskId][role] || ""); }
    public static function taskNpcRuntimeName(taskId:String, role:String):String { return String(_bootstrap.taskNpcLabels[taskId][role + "RuntimeName"] || ""); }
    public static function isCurrent():Boolean {
        if (_bootstrap == undefined || _projection == undefined || _sessionToken == "") return false;
        return context().signature == _confirmedSignature;
    }
}
