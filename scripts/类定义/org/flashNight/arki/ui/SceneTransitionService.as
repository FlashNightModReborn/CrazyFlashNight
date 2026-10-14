import org.flashNight.neur.Server.ServerManager;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.arki.weather.WorldLightingBridge;

/** U12: AS2 owns navigation, cleanup, settlement and save; Web projects the curtain. */
class org.flashNight.arki.ui.SceneTransitionService {
    private static var _installed:Boolean = false;
    private static var _sequence:Number = 0;
    private static var _session:Object = null;
    private static var _retired:Object = null;
    private static var _lastRetiredSend:Number = -1000;
    private static var _background:Object = null;
    private static var _pump:MovieClip;
    public static var sendOverride:Function = null;

    /** Visual readiness is separate from the business SceneReady event. */
    public static function loadBackground(world:Object, url:String, target:Object):Void {
        retireBackgroundListener(_background);
        var ticket:Object = {world:world,identity:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world),
            scene:WorldLightingBridge.sceneNumber(),target:target,started:getTimer(),
            bytesComplete:false,initialized:false,ready:false,failed:false,frames:0,loader:new MovieClipLoader()};
        _background = ticket;
        ticket.listener = {
            ticket:ticket,
            onLoadComplete:function(loaded:MovieClip):Void { SceneTransitionService.backgroundBytesLoaded(this.ticket,loaded); },
            onLoadInit:function(loaded:MovieClip):Void { SceneTransitionService.backgroundLoaded(this.ticket,loaded,false); },
            onLoadError:function(loaded:MovieClip, code:String, status:Number):Void { SceneTransitionService.backgroundLoaded(this.ticket,loaded,true); }
        };
        ticket.loader.addListener(ticket.listener);
        if (!ticket.loader.loadClip(url,target)) backgroundLoaded(ticket,target,true);
    }
    private static function retireBackgroundListener(ticket:Object):Void {
        if (ticket.loader != null) ticket.loader.removeListener(ticket.listener);
        if (ticket != null) ticket.loader = null;
    }
    private static function currentBackground(ticket:Object):Boolean {
        return ticket != null && ticket === _background && ticket.world === _root.gameworld
            && ticket.identity === _root.gameworld.__stageReturnWorldIdentity
            && ticket.scene == WorldLightingBridge.sceneNumber();
    }
    private static function backgroundLoaded(ticket:Object, target:Object, error:Boolean):Void {
        if (!currentBackground(ticket) || target !== ticket.target || ticket.initialized || ticket.failed) return;
        ticket.failed = error;
        ticket.initialized = !error;
        // The callback can share a frame with our tick. Two ticks cross a real frame boundary.
        ticket.frames = error ? 0 : 2;
        retireBackgroundListener(ticket);
    }
    private static function backgroundBytesLoaded(ticket:Object, target:Object):Void {
        if (currentBackground(ticket) && target === ticket.target && !ticket.failed) ticket.bytesComplete = true;
    }
    /** Bitmap baking may unload the child before MovieClipLoader can deliver onLoadInit. */
    public static function backgroundBaked(world:Object, background:Object):Void {
        var ticket:Object = _background;
        if (!currentBackground(ticket) || !ticket.bytesComplete || world !== ticket.world
            || background !== world.背景 || background.外部动画加载壳mc !== ticket.target) return;
        backgroundLoaded(ticket,ticket.target,false);
    }
    private static function advanceBackgroundFrame():Void {
        var ticket:Object = _background;
        if (!currentBackground(ticket)) return;
        if (ticket.initialized && ticket.frames > 0 && --ticket.frames == 0) ticket.ready = true;
        var now:Number = getTimer();
        if (!ticket.initialized && !ticket.failed && (now < ticket.started || now-ticket.started >= 30000)) {
            ticket.failed = true;
            retireBackgroundListener(ticket);
        }
    }
    private static function backgroundReady(s:Object):Boolean {
        var ticket:Object = _background;
        // Inline/base scenes have no external background load to wait for.
        if (ticket == null || ticket.identity !== s.readyIdentity) return true;
        if (!currentBackground(ticket)) return false;
        if (ticket.failed) {
            // Enter the existing loading-error timeline and its one-shot retry/return authority.
            s.fade.gotoAndStop(37);
            return false;
        }
        return ticket.ready === true;
    }

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        org.flashNight.dev.PanelTiming.install();
        _root.gameCommands["sceneTransitionPresented"] = function(p:Object):Void {
            org.flashNight.arki.ui.SceneTransitionService.presented(p);
        };
        _root.gameCommands["sceneTransitionAction"] = function(p:Object):Void {
            org.flashNight.arki.ui.SceneTransitionService.action(p);
        };
        // Root facades keep the class closure in asLoader; main's timeline must not relink it.
        _root.开始Web过场 = function(fade:Object):Void { org.flashNight.arki.ui.SceneTransitionService.begin(fade); };
        _root.设置Web过场提示 = function(fade:Object,text:String):Void { org.flashNight.arki.ui.SceneTransitionService.setTip(fade,text); };
        _root.等待Web过场遮罩 = function(fade:Object):Void { org.flashNight.arki.ui.SceneTransitionService.awaitCovered(fade); };
        _root.等待Web过场揭幕 = function(fade:Object):Void { org.flashNight.arki.ui.SceneTransitionService.awaitReveal(fade); };
        _root.完成Web清场 = function(fade:Object):Boolean { return org.flashNight.arki.ui.SceneTransitionService.cleanupCompleted(fade); };
        _root.完成Web场景初始化 = function(fade:Object):Void { org.flashNight.arki.ui.SceneTransitionService.initializationCompleted(fade); };
        _root.显示Web加载失败 = function(fade:Object):Void { org.flashNight.arki.ui.SceneTransitionService.failed(fade); };
        _root.清理Web过场 = function():Void { org.flashNight.arki.ui.SceneTransitionService.clear(); };
        EventBus.getInstance().subscribe("SceneReady", onSceneReady, null);
        _pump = _root.createEmptyMovieClip("SceneTransitionFrameClip", _root.getNextHighestDepth());
        _pump.onEnterFrame = function():Void { org.flashNight.arki.ui.SceneTransitionService.tick(); };
    }
    // Preserve the original data authority, one-shot LoadingImage and strict Unlock comparison.
    public static function backgroundList():Array {
        var data:Object = _root.加载背景列表;
        if (!data) return ["Andy","TheGirl","Blue","ShopGirl","Boy","Pig","King","过场1","过场2","武器"];
        if (typeof data.本次背景 == "string") {
            var explicit:Array = [data.本次背景];
            data.本次背景 = null;
            return explicit;
        }
        var battle:Boolean = _root.关卡标志 == "wuxianguotu_1";
        var stages:Array = _root.初期关卡列表;
        for (var i:Number=0; i<stages.length; i++) if (_root.关卡标志 == stages[i]) battle = true;
        var source:Array = battle ? data.关卡背景 : data.基地背景;
        var result:Array = [];
        for (var j:Number=0; j<source.length; j++) {
            var image:Object = source[j];
            if (typeof image == "string") result.push(image);
            else if (typeof image.Name == "string" && (_root.主线任务进度+1) > image.Unlock) result.push(image.Name);
        }
        return result;
    }
    public static function imageId(name:String):String {
        if (name == "BLue") return "Blue";
        switch (name) {
            case "Andy": case "TheGirl": case "Blue": case "ShopGirl": case "Boy":
            case "Pig": case "King": case "过场1": case "过场2": case "武器":
            case "7代主角1": case "7代主角2": case "黑铁众": case "诺亚方舟1": return name;
        }
        return "Andy";
    }
    public static function begin(fade:Object):Void {
        install();
        // An accepted jump can publish while the map still owns its pause lease.
        // Frame 2 re-enters this same cover without replacing its receipt or one-shot image.
        if (owns(_session,fade) && _session.phase == "cover") return;
        clear();
        _retired = null;
        var list:Array = backgroundList();
        var identity:Object = {};
        fade.__transitionProjectionIdentity = identity;
        fade.__returnFadeActive = true;
        _session = {requestId:"tr:"+(++_sequence),revision:1,phase:"cover",fade:fade,identity:identity,
            imageId:imageId(list.length ? String(list[random(list.length)]) : "Andy"),tip:"",
            targetScene:WorldLightingBridge.sceneNumber(),oldWorld:_root.gameworld.__stageReturnWorldIdentity,
            worldReady:false,worldPresented:false,covered:false,revealed:false,actionSent:false,lastSend:-1000,
            report:org.flashNight.arki.scene.StageRunSession.parallelReturnReport(fade.__stageReturnToken),
            reportVisible:true,reportHandoff:false};
        _session.timingStarted = org.flashNight.dev.PanelTiming.start();
        // A retry carries the existing business session; it cannot create another
        // report or reset a write whose outcome is still unknown.
        if (_session.report != null && org.flashNight.arki.item.LootContainerService.hasActiveStashedReport(String(_session.report.runId)))
            _session.reportHandoff = true;
        publish();
    }
    private static function owns(s:Object, fade:Object):Boolean {
        return s != null && fade != null && s.fade == fade
            && fade.__transitionProjectionIdentity === s.identity;
    }
    /** 呈现等待与第 17 帧初始化标记分离；报告开窗须等成功尾帧或明确取消撤幕。 */
    public static function isPresentationPending():Boolean {
        return owns(_session,_root.淡出动画);
    }
    public static function setTip(fade:Object, text:String):Void {
        var s:Object = _session;
        if (!owns(s,fade)) return;
        s.tip = typeof text == "string" ? text.substr(0,2048) : "";
        s.revision++;
        publish();
    }
    // Frame 5 is before the existing frame-6 cleanup. A missing Web receipt never grants cleanup.
    public static function awaitCovered(fade:Object):Void {
        if (!owns(_session,fade)) begin(fade);
        if (!_session.covered) fade.stop();
    }
    // Frame 30 precedes the old fade-away. SceneReady is asynchronous, not a frame-13 receipt.
    public static function awaitReveal(fade:Object):Void {
        var s:Object = _session;
        if (!owns(s,fade)) { fade.stop(); return; }
        if (!s.revealed) fade.stop();
        requestReveal();
    }
    // Web 已接管淡出；保留至少一次 EnterFrame 边界，然后越过纯等待帧。
    // 只有原清场成功/第 17 帧业务收尾能够安排跳帧，Web 回执不能替代这些步骤。
    public static function cleanupCompleted(fade:Object):Boolean {
        if (queueAdvance(fade,6,13)) {
            org.flashNight.dev.PanelTiming.finish("transition.cleanup_complete",_session.timingStarted,_sequence);
            return true;
        }
        // 重复完成回调仍由已安排的帧边界接管，不能误触发旧时间线续播。
        return owns(_session,fade) && _session.advance != null
            && _session.advance.fromFrame == 6;
    }
    public static function initializationCompleted(fade:Object):Void {
        if (queueAdvance(fade,17,30))
            org.flashNight.dev.PanelTiming.finish("transition.initialization_complete",_session.timingStarted,_sequence);
    }
    private static function queueAdvance(fade:Object, fromFrame:Number, toFrame:Number):Boolean {
        var s:Object = _session;
        if (!owns(s,fade) || !s.covered || fade._currentframe != fromFrame
                || s.phase == "error" || s.phase == "reveal" || s.advance != null
                || typeof fade.gotoAndPlay != "function") return false;
        // 第一次 tick 可能属于当前帧，第二次 tick 必定经过下一次帧边界。
        s.advance = {fromFrame:fromFrame,toFrame:toFrame,ticks:2};
        fade.stop();
        return true;
    }
    private static function onSceneReady(world:Object, token:String, identity:Object):Void {
        var s:Object = _session;
        if (s != null && s.calibrationOwner != null) return;
        if (!owns(s,_root.淡出动画) || world != _root.gameworld || identity == null
            || identity !== _root.gameworld.__stageReturnWorldIdentity || identity === s.oldWorld) return;
        if (s.worldReady && (s.readyIdentity !== identity || s.targetScene != WorldLightingBridge.sceneNumber())) {
            s.worldPresented = false; s.revision++;
        }
        if (!s.worldReady) org.flashNight.dev.PanelTiming.finish("transition.scene_ready",s.timingStarted,_sequence);
        s.worldReady = true;
        s.readyWorld = world;
        s.readyIdentity = identity;
        s.arrivalToken = token;
        s.targetScene = WorldLightingBridge.sceneNumber();
        requestReveal();
    }

    /** Presentation-only admission for the exact no-player calibration world. */
    public static function calibrationWorldReady(world:Object, identity:Object, fade:Object,
            projectionIdentity:Object, owner:Object, context:Object, onReleased:Function):Boolean {
        var s:Object = _session;
        if (!owns(s,fade) || fade != _root.淡出动画 || projectionIdentity == null
                || projectionIdentity !== s.identity || owner == null || context == null
                || typeof onReleased != "function" || s.report != null || s.covered !== true
                || (s.phase != "cover" && s.phase != "loading")
                || world != _root.gameworld || world._arenaCalibrationStage !== true
                || identity == null || identity !== _root.gameworld.__stageReturnWorldIdentity
                || identity === s.oldWorld || (s.calibrationOwner != null && s.calibrationOwner !== owner)) return false;
        if (s.calibrationOwner != null) {
            return s.calibrationContext === context && s.readyIdentity === identity
                && s.calibrationReleased === onReleased && s.targetScene == WorldLightingBridge.sceneNumber();
        }
        s.calibrationOwner = owner;
        s.calibrationContext = context;
        s.calibrationReleased = onReleased;
        s.worldReady = true;
        s.readyWorld = world;
        s.readyIdentity = identity;
        s.targetScene = WorldLightingBridge.sceneNumber();
        requestReveal();
        return true;
    }
    private static function requestReveal():Void {
        var s:Object = _session;
        if (s == null || !owns(s,s.fade) || !s.worldReady || s.fade._currentframe != 30
            || s.phase == "error" || s.phase == "reveal") return;
        if (s.readyWorld != _root.gameworld
                || s.readyIdentity !== _root.gameworld.__stageReturnWorldIdentity
                || s.targetScene != WorldLightingBridge.sceneNumber()) return;
        if (!backgroundReady(s)) return;
        org.flashNight.dev.PanelTiming.finish("transition.reveal_requested",s.timingStarted,_sequence);
        s.phase = "reveal"; s.revision++; publish();
    }
    public static function failed(fade:Object):Void {
        if (!owns(_session,fade)) begin(fade);
        var s:Object = _session;
        s.phase = "error"; s.revision++; s.actionSent = false;
        fade.__returnFadeActive = false;
        publish();
    }
    public static function presented(p:Object):Void {
        var s:Object = _session;
        if (p == null || !owns(s,s.fade) || p.requestId !== s.requestId
            || typeof p.revision != "number" || p.revision < 1 || p.revision > s.revision
            || p.revision != Math.floor(p.revision)) return;
        if (s.calibrationOwner != null && s.targetScene != WorldLightingBridge.sceneNumber()) return;
        if (p.kind == "covered" && !s.covered && s.phase != "error" && s.phase != "reveal") {
            org.flashNight.dev.PanelTiming.finish("transition.covered",s.timingStarted,_sequence);
            s.covered = true;
            if (s.fade._currentframe == 5) s.fade.play();
        } else if (p.kind == "prepared" && s.report != null && s.phase == "reveal" && p.revision === s.revision
                && s.worldReady && s.readyWorld === _root.gameworld
                && s.readyIdentity === _root.gameworld.__stageReturnWorldIdentity) {
            s.worldPresented = true;
        } else if (p.kind == "handoff" && s.reportHandoff === true && s.worldPresented === true
                && s.phase == "reveal" && p.revision === s.revision && s.worldReady
                && s.readyWorld === _root.gameworld
                && s.readyIdentity === _root.gameworld.__stageReturnWorldIdentity) {
            s.revealed = true;
            // 原终帧没有业务写；普通报告会暂停世界，不能再依赖其下方淡出尾部续帧。
            s.fade.gotoAndStop(36);
            clear();
        } else if (p.kind == "revealed" && !s.revealed && (s.report == null || s.reportVisible !== true)
                && s.phase == "reveal" && p.revision === s.revision && s.worldReady
                && s.readyWorld === _root.gameworld
                && s.readyIdentity === _root.gameworld.__stageReturnWorldIdentity) {
            s.revealed = true;
            if (s.fade._currentframe == 30) s.fade.play();
        }
    }
    public static function action(p:Object):Void {
        var s:Object = _session;
        if (p == null || !owns(s,s.fade) || (s.actionSent && p.verb != "closeReport")
            || p.requestId !== s.requestId || typeof p.revision != "number"
            || p.revision < 1 || p.revision > s.revision || p.revision != Math.floor(p.revision)) return;
        if (p.verb == "closeReport" || p.verb == "manageReport") {
            // This request owns one immutable durable report. Cover/loading/tip advances
            // must not discard an in-flight intent; the Loot owner still decides opening
            // and closure exactly once. No reward authority revision is relaxed here.
            if (s.report == null || s.reportVisible !== true || (s.reportHandoff === true && p.verb != "closeReport") || s.phase == "error") return;
            if (p.verb == "closeReport") {
                if (!org.flashNight.arki.scene.StageRunSession.dismissParallelReport(String(s.report.runId))) return;
                s.reportVisible = false; s.reportHandoff = false; s.actionSent = false; s.revision++; publish();
            } else {
                if (!s.covered) return;
                s.reportHandoff = true; s.actionSent = true; s.revision++; publish();
                org.flashNight.arki.scene.StageRunSession.openParallelReport(String(s.report.runId),s.readyWorld,s.readyIdentity,s.fade.__stageReturnToken);
            }
            return;
        }
        if (p.revision !== s.revision || s.phase != "error" || s.fade._currentframe != 37) return;
        if (p.verb != "retry" && p.verb != "return") return;
        s.actionSent = true;
        s.revision++; publish();
        if (p.verb == "retry") s.fade.淡出跳转帧(_root.关卡标志,s.fade.__stageReturnToken);
        else {
            _root.场景进入位置名 = "出生地";
            _root.从加载失败返回();
        }
        // Unknown delivery / denied authority stays locked; no timer replays navigation.
    }
    public static function tick():Void {
        advanceBackgroundFrame();
        var s:Object = _session;
        if (s == null) {
            if (_retired != null && getTimer()-_lastRetiredSend >= 1000) {
                _lastRetiredSend = getTimer(); send(_retired);
            }
            return;
        }
        // 清场准入拒绝会停回原“空”帧；它是取消，不需要伪造 SceneReady 或失败。
        if (!owns(s,_root.淡出动画) || s.fade._currentframe == 1 || s.fade._currentframe == 36) { clear(); return; }
        if (s.phase == "cover" && s.covered && s.fade._currentframe >= 6) {
            s.phase = "loading"; s.revision++;
        }
        if (s.advance != null) {
            var advance:Object = s.advance;
            if (s.phase == "error" || s.fade._currentframe != advance.fromFrame) s.advance = null;
            else if (--advance.ticks <= 0) {
                s.advance = null;
                s.fade.gotoAndPlay(advance.toFrame);
            }
        }
        if (s.reportHandoff === true && org.flashNight.arki.scene.StageRunSession.parallelReportHandoffState(String(s.report.runId)) == "rejected") {
            s.reportHandoff = false; s.actionSent = false; s.revision++;
            s.tip = "奖励界面暂未能打开，可以先返回基地。";
            publish();
        }
        requestReveal();
        var now:Number = getTimer();
        if (now < s.lastSend || now-s.lastSend >= 500) publish();
    }
    private static function send(payload:Object):Boolean {
        if (sendOverride != null) return sendOverride(payload) === true;
        var sm:ServerManager = ServerManager.getInstance();
        return sm != null && sm.isSocketConnected === true && sm.sendTaskToNode("scene_transition",payload,null) === true;
    }
    private static function publish():Void {
        var s:Object = _session;
        if (s == null) return;
        s.lastSend = getTimer();
        var payload:Object = {version:s.report == null ? 1 : 2,requestId:s.requestId,revision:s.revision,phase:s.phase,
            imageId:s.imageId,tip:s.tip,targetScene:s.targetScene,actionPending:s.actionSent};
        if (s.report != null) { payload.report = s.report; payload.reportVisible = s.reportVisible; payload.reportHandoff = s.reportHandoff; }
        send(payload);
    }
    public static function clear():Void {
        var s:Object = _session;
        var released:Boolean = owns(s,_root.淡出动画) && s.phase == "reveal" && s.fade._currentframe == 36
            && s.revealed === true && s.worldReady === true
            && s.readyWorld === _root.gameworld
            && s.readyIdentity === _root.gameworld.__stageReturnWorldIdentity;
        if (s.calibrationOwner != null && s.targetScene != WorldLightingBridge.sceneNumber()) released = false;
        _session = null;
        if (s != null) {
            _retired = {version:s.report == null ? 1 : 2,requestId:s.requestId,revision:s.revision+1,phase:"hide",
                imageId:s.imageId,tip:s.tip,targetScene:s.targetScene,actionPending:false};
            if (s.report != null) { _retired.report = s.report; _retired.reportVisible = false; _retired.reportHandoff = false; }
            _lastRetiredSend = getTimer(); send(_retired);
            // hide 先于任何会暂停世界的报告开窗；重复 clear 或取消都不发布成功交接。
            if (released) {
                org.flashNight.dev.PanelTiming.finish("transition.released",s.timingStarted,_sequence);
                if (s.calibrationOwner != null) {
                    var callback:Function = s.calibrationReleased;
                    s.calibrationReleased = null;
                    if (typeof callback == "function") callback(s.calibrationOwner,s.calibrationContext,
                        s.readyWorld,s.readyIdentity,s.fade,s.identity);
                } else {
                    EventBus.getInstance().publish("SceneTransitionReleased",s.readyWorld,s.arrivalToken,s.readyIdentity);
                }
            }
        }
    }
}
