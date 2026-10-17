import LiteJSON;
import org.flashNight.arki.merc.ArenaCalibrationService;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.arki.scene.SceneManager;
import org.flashNight.arki.ui.SceneTransitionService;
import org.flashNight.arki.weather.WorldLightingBridge;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.gesh.object.ObjectUtil;

/** 真 AS2 context echo / 延迟 stage callback / phase loader 登记 focused 合同。 */
class org.flashNight.arki.merc.ArenaWorkerProtocolTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var responses:Array;
    private static var loads:Array;
    private static var codec:LiteJSON;
    private static var sequence:Number;
    private static var phaseWorld:MovieClip;
    private static var loaderSawFlag:Boolean;
    private static var loaderSawFaction:Boolean;
    private static var revealSpawns:Number;
    private static var transitionMessages:Array;
    private static var lightingMessages:Array;

    public static function runAllTests():Void {
        passed = 0; failed = 0; sequence = 0;
        responses = []; loads = []; codec = new LiteJSON();
        var saved:Object = {};
        var names:Array = ["server", "gameCommands", "gameworld", "加载游戏世界人物",
            "加载共享场景", "兵种库", "StageInfoDict", "载入关卡数据", "淡出动画",
            "cf7ArenaWorker", "cf7ArenaWorkerId", "cf7ArenaSessionEpoch",
            "斗兽标定模式", "斗兽标定禁存档", "_agentCalibrationNoSave"];
        for (var i:Number = 0; i < names.length; i++) saved[names[i]] = _root[names[i]];
        _root.server = {sendSocketMessage:function(message:String):Boolean {
            org.flashNight.arki.merc.ArenaWorkerProtocolTest.recordResponse(message);
            return true;
        }};
        _root.cf7ArenaWorker = "1";
        _root.cf7ArenaWorkerId = "w01";
        _root.cf7ArenaSessionEpoch = "session01";
        _root.加载游戏世界人物 = undefined;
        ArenaCalibrationService.install();
        ArenaCalibrationService.testOnlySetPendingRun(undefined);

        ArenaCalibrationService.handleRun({callId:1});
        check(last().status == "invalid_case" && last().workerId == undefined,
            "missing context is rejected without manufacturing an echo");
        var invalid:Object = request("invalid");
        invalid.repeatIndex = "1";
        ArenaCalibrationService.handleRun(invalid);
        check(last().status == "invalid_case" && last().attemptId == undefined,
            "malformed typed context cannot enter the runner");
        var valid:Object = request("early");
        ArenaCalibrationService.handleRun(valid);
        check(echoes(last(), valid), "validated loader failure echoes every captured identity");
        check(last().status == "stage_failed", "valid context preserves the real loader failure");
        var foreign:Object = request("foreign");
        foreign.sessionEpoch = "foreign-session";
        ArenaCalibrationService.handleRun(foreign);
        check(last().status == "invalid_case" && last().sessionEpoch == undefined,
            "Worker cannot consume another process session context");

        phaseWorld = _root.createEmptyMovieClip("__arenaWorkerProtocolWorld", _root.getNextHighestDepth());
        _root.gameworld = phaseWorld;
        _root.加载游戏世界人物 = function():Void {};
        _root.加载共享场景 = function():Void {};
        _root.兵种库 = {ProtocolUnit:{兵种名:"ProtocolUnit", hp:100}};
        _root.StageInfoDict = {};
        _root.StageInfoDict["DEATH MATCH角斗场"] = {Type:"无限过图", url:"protocol-fixture.xml"};
        _root.淡出动画 = {淡出跳转帧:function(frameName:String):Void {}};
        _root.载入关卡数据 = function(stageType, url, ready, error, token):Void {
            org.flashNight.arki.merc.ArenaWorkerProtocolTest.recordLoad(ready, error, token);
        };
        StageRunSession.resetForRestart();

        var delayed:Object = request("delayed");
        ArenaCalibrationService.handleRun(delayed);
        check(loads.length == 1, "real handleRun owns one deferred stage load");
        delayed.workerId = "mutated"; delayed.caseHash = "mutated"; delayed.runId = "mutated";
        loads[0].error();
        check(last().workerId == "w01" && last().runId == "delayed-r001"
            && String(last().caseHash).length == 71,
            "delayed failure reads its frozen context instead of the caller object");
        check(last().status == "stage_failed", "deferred loader error remains an actual stage failure");
        var replacement:Object = request("replacement");
        ArenaCalibrationService.handleRun(replacement);
        check(loads.length == 2, "replacement run owns an independent pending stage request");
        var before:Number = responses.length;
        loads[0].error();
        check(responses.length == before, "retired stage error does not answer the replacement");
        loads[1].error();
        check(echoes(last(), replacement), "replacement delayed response retains its own context");

        var abortable:Object = request("abortable");
        ArenaCalibrationService.handleRun(abortable);
        var wrongAbort:Object = request("wrong-abort");
        ArenaCalibrationService.handleAbort(wrongAbort);
        check(last().errors[0].code == "context_mismatch" && !StageRunSession.canStartStage(),
            "foreign abort leaves the current reservation intact");
        var exactAbort:Object = request("abortable");
        ArenaCalibrationService.handleAbort(exactAbort);
        check(last().status == "aborted" && echoes(last(), exactAbort),
            "exact abort response echoes the validated abort context");
        check(StageRunSession.canStartStage(), "exact pending abort releases its own reservation");

        _root.加载游戏世界人物 = function(id:String, name:String, depth:Number, init:Object):MovieClip {
            return org.flashNight.arki.merc.ArenaWorkerProtocolTest.makePhaseUnit(id, name, depth, init);
        };
        var parent:MovieClip = phaseWorld.createEmptyMovieClip("phaseParent", phaseWorld.getNextHighestDepth());
        parent.hp = 100; parent.hp满血值 = 100; parent._arenaCalibrationUnit = true;
        parent._arenaCalibrationRun = "phase-run";
        var parentRecord:Object = {mc:parent, unitType:"ProtocolParent", level:1,
            side:"blue", isEnemy:false, spawnName:"phaseParent"};
        var owner:Object = {runId:"phase-run", blueUnits:[parentRecord], redUnits:[],
            phaseSpawnCount:0, spawnedUnits:[], errors:[], frames:0};
        loaderSawFlag = false; loaderSawFaction = true;
        ArenaCalibrationService.testOnlySetPhaseOwner(owner);
        var child:MovieClip = _root.加载游戏世界人物("ProtocolUnit", "phaseChild",
            phaseWorld.getNextHighestDepth(), {产生源:"phaseParent", 等级:1});
        check(loaderSawFlag, "phase flag reaches the real original loader before initialization");
        check(loaderSawFaction === false, "derived loader receives the registered parent's actual faction");
        check(owner.phaseSpawnCount == 1 && owner.blueUnits.length == 2,
            "pre-marked derived unit is still registered exactly once");
        check(owner.blueUnits[1].parentUnitType == "ProtocolParent"
            && child._arenaCalibrationRun == "phase-run",
            "registration binds the derived unit to its actual run and parent");
        check(owner.blueUnits[1].skillState.cooldownsClear === true
            && owner.blueUnits[1].skillState !== child._arenaCalibrationSkillState,
            "phase registration captures an independent skill initial-state value");
        ArenaCalibrationService.handleSpawnedUnit("ProtocolUnit", "phaseChild", {}, child, parentRecord);
        check(owner.phaseSpawnCount == 1 && owner.blueUnits.length == 2,
            "duplicate callback for an already registered derived unit is ignored");
        var unknown:MovieClip = phaseWorld.createEmptyMovieClip("unknown", phaseWorld.getNextHighestDepth());
        unknown._arenaCalibrationUnit = true;
        ArenaCalibrationService.handleSpawnedUnit("ProtocolUnit", "unknown", {}, unknown, undefined);
        check(unknown._arenaCalibrationUnknown === true && owner.errors.length == 1,
            "an unregistered pre-marked actor is still contamination");
        ArenaCalibrationService.testOnlySetPhaseOwner(undefined);
        check(typeof _root.加载游戏世界人物 == "function",
            "phase fixture restores the original loader after the owned hook");

        testCalibrationRevealGate();
        ArenaCalibrationService.testOnlySetPendingRun(undefined);
        phaseWorld.removeMovieClip();
        StageRunSession.resetForRestart();
        for (i = 0; i < names.length; i++) _root[names[i]] = saved[names[i]];
        trace("ArenaWorkerProtocolTest Tests Passed: " + passed);
        trace("ArenaWorkerProtocolTest Tests Failed: " + failed);
    }

    /** Real pending/reveal/runner path; only external movie loading and Host receipts are fixtures. */
    private static function testCalibrationRevealGate():Void {
        var saved:Object = {};
        var names:Array = ["server", "gameworld", "淡出动画", "加载游戏世界人物", "gameworld层级定位器",
            "帧计时器", "天空盒", "场景转换函数", "soundEffectManager", "当前为战斗地图", "场景转换中",
            "当前通关的关卡", "当前关卡名", "关卡类型", "关卡路径", "无限过图模式", "场景进入位置名",
            "角斗场对手类型", "角斗场roster阵容", "押金", "角斗场奖金", "敌人同伴数", "敌人总数",
            "Xmin", "Xmax", "Ymin", "Ymax", "启用后景", "斗兽标定模式", "斗兽标定禁存档", "_agentCalibrationNoSave"];
        for (var i:Number = 0; i < names.length; i++) saved[names[i]] = _root[names[i]];
        var oldSend:Function = SceneTransitionService.sendOverride;
        var manager:SceneManager = SceneManager.getInstance();
        var oldManagerWorld:MovieClip = manager.gameworld;
        var weather:WeatherSystem = WeatherSystem.getInstance();
        var oldCycle:Boolean = weather.enableDayNightCycle;
        var holder:MovieClip = _root.createEmptyMovieClip("__arenaRevealProtocol", _root.getNextHighestDepth());
        var service:Object = ArenaCalibrationService;
        revealSpawns = 0; transitionMessages = []; lightingMessages = [];
        try {
            _root.server = {isSocketConnected:true,
                sendSocketMessage:function(message:String):Boolean {
                    org.flashNight.arki.merc.ArenaWorkerProtocolTest.recordResponse(message); return true;
                }, sendTaskToNode:function(task:String, payload:Object, extra):Boolean {
                    org.flashNight.arki.merc.ArenaWorkerProtocolTest.recordLighting(task, payload); return true;
                }};
            SceneTransitionService.sendOverride = function(payload:Object):Boolean {
                org.flashNight.arki.merc.ArenaWorkerProtocolTest.recordTransition(payload); return true;
            };
            _root.加载游戏世界人物 = function(id:String, name:String, depth:Number, init:Object):MovieClip {
                return org.flashNight.arki.merc.ArenaWorkerProtocolTest.makeRevealUnit(id, name, depth, init);
            };
            _root.gameworld层级定位器 = {};
            _root.帧计时器 = {当前帧数:0, 帧率:30};
            _root.天空盒 = undefined; _root.场景转换函数 = undefined; _root.soundEffectManager = undefined;
            weather.enableDayNightCycle = false;

            var value:Object = revealFixture(holder, "presentation");
            check(value.ticket != undefined && SceneTransitionService.isPresentationPending()
                && revealSpawns == 0 && value.world.斗兽标定时钟 == undefined,
                "real first run remains pending without actors or clock after stage data and cover");
            check(value.previous === value.world && value.previousIdentity !== value.identity,
                "runner fixture uses a real rebound MovieClip path with a new captured identity");
            ArenaCalibrationService.onCalibrationStageReady(value.world, value.identity, "foreign-token");
            check(lightingMessages.length == 0 && revealSpawns == 0,
                "foreign stage token cannot prepare or release the pending runner");
            ArenaCalibrationService.onCalibrationStageReady(value.world, value.previousIdentity, value.token);
            check(lightingMessages.length == 0 && revealSpawns == 0,
                "captured old same-path world identity cannot prepare the replacement");
            ArenaCalibrationService.onCalibrationStageReady(value.world, value.identity, value.token);
            var light:Object = lightingMessages[lightingMessages.length - 1];
            check(value.ticket.presentationRegistered === true && light.ready === true
                && light.scene == WorldLightingBridge.sceneNumber() && value.world.斗兽标定镜头 != undefined
                && revealSpawns == 0 && value.world.斗兽标定时钟 == undefined,
                "empty visual world and native lighting ready precede dedicated reveal admission");
            var lights:Number = lightingMessages.length;
            ArenaCalibrationService.onCalibrationStageReady(value.world, value.identity, value.token);
            check(lightingMessages.length == lights && revealSpawns == 0,
                "duplicate visual readiness does not prepare or start the run twice");
            var foreign:Object = request("presentation-foreign");
            ArenaCalibrationService.handleRun(foreign);
            check(last().errors[0].code == "stage_transition_pending" && echoes(last(), foreign)
                && service["_pendingStageRequest"] === value.ticket && revealSpawns == 0,
                "another run cannot displace the committed presentation waiter");
            org.flashNight.arki.camera.HorizontalScroller.update();
            value.fade._currentframe = 30; SceneTransitionService.awaitReveal(value.fade);
            var reveal:Object = transitionMessages[transitionMessages.length - 1];
            check(reveal.phase == "reveal" && revealSpawns == 0 && value.world.斗兽标定时钟 == undefined,
                "missing native Web reveal receipt leaves actors and timer blocked");
            SceneTransitionService.presented({requestId:reveal.requestId, revision:reveal.revision - 1, kind:"revealed"});
            check(revealSpawns == 0 && value.world.斗兽标定时钟 == undefined,
                "stale reveal receipt cannot begin the battle");
            SceneTransitionService.presented({requestId:reveal.requestId, revision:reveal.revision, kind:"revealed"});
            check(revealSpawns == 0 && value.world.斗兽标定时钟 == undefined,
                "exact reveal receipt still waits for the original successful tail");
            value.fade._currentframe = 36; SceneTransitionService.tick();
            check(revealSpawns == 2 && typeof value.world.斗兽标定时钟.onEnterFrame == "function"
                && echoes(service["_active"].context, value.params) && service["_pendingStageRequest"] == undefined,
                "real frame-36 release consumes pending once and starts the exact two actors and clock");
            SceneTransitionService.clear();
            ArenaCalibrationService.onCalibrationPresentationReleased(value.ticket, value.ticket.runContext,
                value.world, value.identity, value.fade, value.projection);
            check(revealSpawns == 2, "duplicate retired release cannot restart the active run");
            ArenaCalibrationService.tick(); ArenaCalibrationService.tick();
            check(last().status == "timeout" && echoes(last(), value.params) && _root.斗兽标定模式 === false
                && value.world.斗兽标定时钟 == undefined,
                "normal finish removes its clock and clears root mode after the revealed run");
            var warm:Object = request("presentation-warm"); warm.timeoutFrames = 1;
            ArenaCalibrationService.handleRun(warm);
            check(revealSpawns == 4 && typeof value.world.斗兽标定时钟.onEnterFrame == "function",
                "same revealed world admits warm repeats despite the normal root mode reset");
            ArenaCalibrationService.tick(); ArenaCalibrationService.tick();
            check(last().status == "timeout" && echoes(last(), warm) && value.world.斗兽标定时钟 == undefined,
                "warm repeat finishes through the original runner with its own exact context");
            WorldLightingBridge.sceneChanged();
            ArenaCalibrationService.handleRun(request("presentation-new-epoch"));
            check(last().errors[0].code == "calibration_presentation_pending" && revealSpawns == 4
                && value.world.斗兽标定时钟 == undefined,
                "same MovieClip with a new native scene epoch cannot reuse the completed reveal");

            var cancelled:Object = revealFixture(holder, "presentation-cancelled");
            ArenaCalibrationService.onCalibrationStageReady(cancelled.world, cancelled.identity, cancelled.token);
            ArenaCalibrationService.onCalibrationStageInitializationFailed(cancelled.token);
            check(last().status == "stage_failed" && echoes(last(), cancelled.params) && revealSpawns == 4,
                "exact initialization failure retires a pending visual waiter without spawning");
            finishRevealFixture(cancelled);
            check(service["_pendingStageRequest"] == undefined && revealSpawns == 4
                && cancelled.world.斗兽标定时钟 == undefined,
                "a later real successful tail cannot revive a cancelled pending run");
            ArenaCalibrationService.onCalibrationPresentationReleased(cancelled.ticket, cancelled.ticket.runContext,
                cancelled.world, cancelled.identity, cancelled.fade, cancelled.projection);
            check(revealSpawns == 4, "an explicitly late cancelled callback also has no runner authority");

            // Corrupt one pending identity field after registration: the real SceneTransition
            // callback still carries its frozen original value and must reject every mismatch.
            var keys:Array = ["workerId", "sessionEpoch", "assignmentId", "attemptId", "batchId",
                "manifestHash", "caseId", "caseHash", "runId", "repeatIndex"];
            for (i = 0; i < keys.length; i++) {
                value = revealFixture(holder, "presentation-context-" + i);
                ArenaCalibrationService.onCalibrationStageReady(value.world, value.identity, value.token);
                if (i == 0) {
                    ArenaCalibrationService.onCalibrationPresentationReleased(cancelled.ticket, cancelled.ticket.runContext,
                        value.world, value.identity, cancelled.fade, cancelled.projection);
                    check(service["_pendingStageRequest"] === value.ticket && revealSpawns == 4,
                        "old pending callback cannot consume a new waiter even after same-path world replacement");
                }
                var originalContext:Object = value.ticket.params._arenaContext;
                var altered:Object = ObjectUtil.clone(originalContext);
                altered[keys[i]] = keys[i] == "repeatIndex" ? 2 : "foreign-context";
                value.ticket.params._arenaContext = altered;
                finishRevealFixture(value);
                check(service["_pendingStageRequest"] === value.ticket && revealSpawns == 4
                    && value.world.斗兽标定时钟 == undefined,
                    "real release rejects changed pending context field: " + keys[i]);
                value.ticket.params._arenaContext = originalContext;
                ArenaCalibrationService.onCalibrationStageInitializationFailed(value.token);
            }
        } finally {
            ArenaCalibrationService.testOnlySetPhaseOwner(undefined);
            ArenaCalibrationService.testOnlySetPendingRun(undefined);
            SceneTransitionService.clear();
            SceneTransitionService.sendOverride = oldSend;
            var cameraWorld:MovieClip=_root.gameworld;
            org.flashNight.arki.camera.HorizontalScroller.releaseScene(cameraWorld,cameraWorld.__stageReturnWorldIdentity,
                org.flashNight.arki.camera.HorizontalScroller.sceneScope(cameraWorld,cameraWorld.__stageReturnWorldIdentity));
            holder.removeMovieClip(); manager.gameworld = oldManagerWorld;
            weather.enableDayNightCycle = oldCycle;
            StageRunSession.resetForRestart();
            for (i = 0; i < names.length; i++) _root[names[i]] = saved[names[i]];
        }
    }

    private static function revealFixture(holder:MovieClip, name:String):Object {
        SceneTransitionService.clear(); ArenaCalibrationService.testOnlySetPendingRun(undefined);
        StageRunSession.resetForRestart();
        _root.当前为战斗地图 = false; _root.场景转换中 = false; _root.斗兽标定模式 = false;
        if (holder.world != undefined) {
            var priorWorld:MovieClip=holder.world;
            org.flashNight.arki.camera.HorizontalScroller.releaseScene(priorWorld,priorWorld.__stageReturnWorldIdentity,
                org.flashNight.arki.camera.HorizontalScroller.sceneScope(priorWorld,priorWorld.__stageReturnWorldIdentity));
            priorWorld.removeMovieClip();
        }
        var previous:MovieClip = holder.createEmptyMovieClip("world", 1); _root.gameworld = previous;
        var previousIdentity:Object = StageReturnFlow.worldIdentity(previous);
        var fade:Object = {_currentframe:1, play:function():Void {}, stop:function():Void {},
            淡出跳转帧:function(frame:String):Boolean {
                return org.flashNight.arki.merc.ArenaWorkerProtocolTest.beginRevealFade(this);
            }};
        _root.淡出动画 = fade;
        var params:Object = request(name); params.timeoutFrames = 1;
        ArenaCalibrationService.handleRun(params);
        var load:Object = loads[loads.length - 1]; load.ready({});
        var service:Object = ArenaCalibrationService;
        var ticket:Object = service["_pendingStageRequest"];
        previous.removeMovieClip();
        var world:MovieClip = holder.createEmptyMovieClip("world", 1); _root.gameworld = world;
        world._arenaCalibrationStage = true;
        world.createEmptyMovieClip("deadbody", -3); world.deadbody.layers = [];
        world.createEmptyMovieClip("背景", 2); world.createEmptyMovieClip("地图", 3);
        SceneManager.getInstance().gameworld = world;
        var identity:Object = StageReturnFlow.worldIdentity(world);
        WorldLightingBridge.sceneChanged();
        return {params:params, ticket:ticket, token:load.token, previous:previous, previousIdentity:previousIdentity,
            world:world, identity:identity, fade:fade, projection:fade.__transitionProjectionIdentity};
    }
    public static function beginRevealFade(fade:Object):Boolean {
        fade._currentframe = 5; SceneTransitionService.begin(fade);
        var cover:Object = transitionMessages[transitionMessages.length - 1];
        SceneTransitionService.presented({requestId:cover.requestId, revision:cover.revision, kind:"covered"});
        fade._currentframe = 17; SceneTransitionService.tick(); SceneTransitionService.setTip(fade, "protocol visual stage");
        return true;
    }
    private static function finishRevealFixture(value:Object):Void {
        org.flashNight.arki.camera.HorizontalScroller.update();
            value.fade._currentframe = 30; SceneTransitionService.awaitReveal(value.fade);
        var reveal:Object = transitionMessages[transitionMessages.length - 1];
        SceneTransitionService.presented({requestId:reveal.requestId, revision:reveal.revision, kind:"revealed"});
        value.fade._currentframe = 36; SceneTransitionService.tick();
    }
    public static function recordTransition(payload:Object):Void { transitionMessages.push(payload); }
    public static function recordLighting(task:String, payload:Object):Void {
        if (task == "world_lighting") lightingMessages.push(payload);
    }
    public static function makeRevealUnit(id:String, name:String, depth:Number, init:Object):MovieClip {
        revealSpawns++;
        var mc:MovieClip = _root.gameworld.createEmptyMovieClip(name, depth);
        for (var key:String in init) mc[key] = init[key];
        mc.hp = 100; mc.hp满血值 = 100;
        mc._arenaCalibrationSkillState = {cacheKey:"reveal", cacheHit:false, skillCount:1,
            cooldownsClear:true, definitionSignature:"reveal-definition"};
        return mc;
    }

    public static function recordResponse(message:String):Void { responses.push(codec.parse(message)); }
    public static function recordLoad(ready:Function, error:Function, token:String):Void {
        loads.push({ready:ready, error:error, token:token});
    }
    public static function makePhaseUnit(id:String, name:String, depth:Number, init:Object):MovieClip {
        loaderSawFlag = init._arenaCalibrationUnit === true;
        loaderSawFaction = init.是否为敌人;
        var mc:MovieClip = phaseWorld.createEmptyMovieClip(name, depth);
        for (var key:String in init) mc[key] = init[key];
        mc.hp = 100; mc.hp满血值 = 100;
        mc._arenaCalibrationSkillState = {cacheKey:"phase", cacheHit:false, skillCount:1,
            cooldownsClear:true, definitionSignature:"phase-definition"};
        return mc;
    }
    private static function request(name:String):Object {
        return {callId:++sequence, workerId:"w01", sessionEpoch:"session01",
            assignmentId:"assignment01", attemptId:"attempt01", batchId:name,
            manifestHash:"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            caseId:"case01", caseHash:"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
            runId:name + "-r001", repeatIndex:1,
            blueRoster:[{兵种:"ProtocolUnit", 等级:1}], redRoster:[{兵种:"ProtocolUnit", 等级:1}]};
    }
    private static function last():Object { return responses[responses.length - 1]; }
    private static function echoes(actual:Object, expected:Object):Boolean {
        var keys:Array = ["workerId", "sessionEpoch", "assignmentId", "attemptId",
            "batchId", "manifestHash", "caseId", "caseHash", "runId", "repeatIndex"];
        for (var i:Number = 0; i < keys.length; i++) {
            if (actual[keys[i]] !== expected[keys[i]]) return false;
        }
        return true;
    }
    private static function check(condition:Boolean, label:String):Void {
        if (condition) { passed++; trace("[PASS] " + label); }
        else { failed++; trace("[FAIL] " + label); }
    }
}
