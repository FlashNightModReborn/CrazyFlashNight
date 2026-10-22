import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.audio.AudioBridge;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.neur.Server.SaveManager;

/** Real BookRun/CF6/BookComic integration with in-memory transport and save boundaries only. */
class org.flashNight.arki.scene.Cf6BookRunStoryTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var AUDIO_SESSION:String = "01234567-89ab-4cde-8f01-23456789abcd";
    private static var AUDIO_DIGEST:String =
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    private static var requests:Array;
    private static var responses:Array;
    private static var timers:Array;
    private static var roomCalls:Array;
    private static var bossCalls:Array;
    private static var dialogueCalls:Array;
    private static var telemetryCalls:Array;
    private static var dirty:Number;
    private static var rewardPending:Boolean;
    private static var nextCallId:Number;

    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] Cf6BookRunStory: " + message); }
    }
    private static function definition():Object {
        var ids:Array = ["TUTORIAL", "A01", "A02", "A03", "A04", "A05", "A06", "A08"];
        var maps:Array = [];
        for (var i:Number = 0; i < ids.length; i++) {
            maps.push({id:ids[i], dialogue:[], mechanism:{assetScale:1, layers:[], fixtureId:ids[i]}});
        }
        return {id:"cf6-sting", stageName:"书中历险-毒刺行动", maps:maps};
    }
    private static function audioResult(request:Object):Object {
        return {wireRevision:2, requestId:request.requestId,
            audioSessionId:request.audioSessionId,
            audioReadyGeneration:request.audioReadyGeneration, deviceGeneration:"9",
            operation:request.operation, completionState:"started", category:"ok",
            stage:"native_start", nativeCode:0, hresult:0,
            decoderBackend:"builtin", messageKey:"audio.bgm.result"};
    }
    private static function setup(bookId:String):Void {
        var api:Object = BookRunService;
        var comic:Object = BookComicService;
        var clock:Object = BookRunClock;
        api._chapter = null; api._ending = null;
        api._cf6PlanOwner = null; api._cf6BossPlans = {};
        if (api._chapterWatch != null) delete api._chapterWatch.onEnterFrame;
        clock._session = null;
        if (clock._watch != null) delete clock._watch.onEnterFrame;
        BookComicService.onTransportDisconnected();
        if (comic._watch != null) delete comic._watch.onEnterFrame;
        if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("cf6BookRunFixtureWorld", 9290);
        _root.savePath = "bookrun_cf6bookrun_fixture";
        var run:Object = {slot:_root.savePath, bookId:bookId,
            seed:17, planSeed:17, startedAt:100, outcome:"active"};
        if (bookId === "cf6-sting") run.routeId = "historical";
        _root._saveExt = {bookRun:run};
        var definitionApi:Object = BookDefinition;
        definitionApi._cf6 = definition();
        if (bookId === "lee-trial") {
            var lee:Object = LeeTrialDefinition;
            lee._data = {stageName:"CF6 integration Lee fixture"};
        }
        _root.当前关卡名 = bookId === "cf6-sting" ? "书中历险-毒刺行动"
            : (bookId === "lee-trial" ? LeeTrialDefinition.get().stageName
            : BookDefinition.get("repair-campus").stageName);
        _root.淡出动画 = {__returnFadeActive:false};
        _root.场景转换中 = false;
        _root.技能点数 = 41;
        requests = []; responses = []; timers = []; roomCalls = []; bossCalls = [];
        dialogueCalls = []; telemetryCalls = [];
        dirty = 0; rewardPending = false; nextCallId = 0;
        _root.帧计时器 = {添加单次任务:function(callback:Function, delay:Number):Void {
            org.flashNight.arki.scene.Cf6BookRunStoryTest.timers.push(callback);
        }};
        _root.存档系统 = {markDirty:function():Void {
            org.flashNight.arki.scene.Cf6BookRunStoryTest.dirty++;
        }};
        _root.server = {isSocketConnected:true,
            sendTaskWithCallback:function(task:String, p:Object, extra:Object, cb:Function):Void {
                org.flashNight.arki.scene.Cf6BookRunStoryTest.requests.push(p.initData);
            },
            sendTaskToNode:function(task:String, payload:Object):Boolean {
                org.flashNight.arki.scene.Cf6BookRunStoryTest.responses.push(payload);
                return true;
            }};
        var audioTransport:Object = {isSocketConnected:true};
        audioTransport.sendTaskToNode = function(task:String, payload:Object, extra:Object):Boolean {
            var request:Object = {};
            for (var key:String in payload) {
                if (Object.prototype.hasOwnProperty.call(payload, key)) request[key] = payload[key];
            }
            AudioBridge.handleBgmResult(org.flashNight.arki.scene.Cf6BookRunStoryTest.audioResult(request));
            return true;
        };
        AudioBridge._resetForTests();
        AudioBridge._setTransportForTests(audioTransport);
        AudioBridge.handleAudioReady({task:"audio_ready", wireRevision:2,
            audioSessionId:AUDIO_SESSION, audioReadyGeneration:"42", deviceGeneration:"9",
            loaded:0, failed:0, overrides:0, capabilityDigest:AUDIO_DIGEST});
        PauseManager.set(false, "manual");
    }
    private static function latestPacket():Object {
        var p:Object = requests[requests.length - 1];
        nextCallId++;
        return {v:1, callId:nextCallId, presentationId:p.presentationId,
            slot:p.slot, sceneId:p.sceneId, pageId:p.pageId,
            panelInstanceId:"cf6.bookrun.fixture." + p.presentationId, reason:"continue"};
    }
    private static function replaceWorld():Void {
        if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("cf6BookRunFixtureWorld", 9290);
    }
    private static function finishFinalSegments():Void {
        var story:Object = latestPacket();
        BookComicService.handle("prepared", story);
        BookComicService.handle("finish", story);
        var credits:Object = latestPacket();
        BookComicService.handle("prepared", credits);
        BookComicService.handle("finish", credits);
    }
    private static function testChapterPreparedHandoff():Void {
        setup("cf6-sting");
        var api:Object = BookRunService;
        BookRunService.playChapter(7);
        var chapter:Object = api._chapter;
        var watch:Function = api._chapterWatch.onEnterFrame;
        check(requests.length == 1 && requests[0].pageId == "cf6-s4"
                && chapter.storyActive === true && roomCalls.length == 0,
            "chapter watcher opens s4 without entering A08");
        watch();
        check(requests.length == 1 && roomCalls.length == 0,
            "the real chapter watch cannot reopen an active story");
        var first:Object = latestPacket();
        BookComicService.handle("prepared", first);
        BookComicService.handle("finish", first);
        check(requests.length == 2 && requests[1].pageId == "cf6-s5"
                && roomCalls.length == 0 && dialogueCalls.length == 0,
            "prepared s4 advances only to s5");
        BookComicService.handle("finish", first);
        watch();
        check(requests.length == 2 && roomCalls.length == 0,
            "old s4 and repeated scene release cannot skip s5");
        var second:Object = latestPacket();
        BookComicService.handle("prepared", second);
        check(roomCalls.length == 0 && dirty == 0,
            "s5 preparation alone is not room continuation or settlement");
        BookComicService.handle("finish", second);
        check(roomCalls.length == 1 && roomCalls[0].mapId == "A08"
                && roomCalls[0].owner === StageReturnFlow.worldIdentity(_root.gameworld)
                && roomCalls[0].config.fixtureId == "A08"
                && bossCalls.length == 1 && dialogueCalls.length == 1,
            "only prepared and finished s4/s5 enter the real A08 continuation once");
        check(chapter.started === true && chapter.storyActive === false
                && api._chapterWatch.onEnterFrame === undefined
                && _root._saveExt.bookRun.outcome == "active" && dirty == 0,
            "room handoff retires its watch without settling the run");
        BookComicService.handle("finish", first);
        BookComicService.handle("finish", second);
        watch(); BookRunService.presentChapter();
        EventBus.getInstance().publish("SceneTransitionReleased", _root.gameworld, "",
            StageReturnFlow.worldIdentity(_root.gameworld));
        check(roomCalls.length == 1 && bossCalls.length == 1 && dialogueCalls.length == 1
                && requests.length == 2,
            "duplicate presentations and scene releases cannot restart the completed room");
    }
    private static function testChapterRejectsStaleContinuation():Void {
        var modes:Array = ["world", "slot", "run"];
        for (var i:Number = 0; i < modes.length; i++) {
            setup("cf6-sting");
            var api:Object = BookRunService;
            BookRunService.playChapter(7);
            var first:Object = latestPacket();
            BookComicService.handle("prepared", first);
            BookComicService.handle("finish", first);
            var second:Object = latestPacket();
            BookComicService.handle("prepared", second);
            var watch:Function = api._chapterWatch.onEnterFrame;
            if (modes[i] == "world") replaceWorld();
            else if (modes[i] == "slot") _root.savePath = "bookrun_cf6bookrun_other";
            else {
                var replacement:Object = org.flashNight.gesh.object.PersistedSnapshot.clone(_root._saveExt.bookRun);
                replacement.startedAt++;
                _root._saveExt.bookRun = replacement;
            }
            BookComicService.handle("finish", second);
            watch(); BookRunService.presentChapter();
            check(roomCalls.length == 0 && bossCalls.length == 0 && dialogueCalls.length == 0
                    && api._chapter == null && requests.length == 2,
                "stale s5 cannot enter a room after " + modes[i] + " replacement");
            check(dirty == 0 && _root._saveExt.bookRun.outcome == "active",
                "stale chapter " + modes[i] + " callback has no settlement side effect");
        }
    }
    private static function testFinalPendingBarrier():Void {
        setup("cf6-sting");
        rewardPending = true;
        var api:Object = BookRunService;
        var originalRun:Object = _root._saveExt.bookRun;
        BookRunService.finish("victory");
        var ending:Object = api._ending;
        check(requests.length == 1 && requests[0].pageId == "cf6-s7"
                && ending.storyActive === true && originalRun.outcome == "active"
                && dirty == 0 && BookRunService.hasUnsettledOutcome(),
            "CF6 victory holds outcome at s7 even before credits");
        BookRunService.reconcileOutcome(); BookRunService.reconcileOutcome();
        check(requests.length == 1 && timers.length == 0 && dirty == 0,
            "reconcile cannot duplicate an active final presentation");
        var story:Object = latestPacket();
        BookComicService.handle("prepared", story);
        BookComicService.handle("finish", story);
        check(requests.length == 2 && requests[1].pageId == "cf6-end"
                && originalRun.outcome == "active" && dirty == 0,
            "s7 proceeds to credits rather than campus, Lee, cover, or outcome");
        var credits:Object = latestPacket();
        BookComicService.handle("prepared", credits);
        BookComicService.handle("finish", credits);
        check(ending.storyCompleted === true && originalRun.outcome == "active"
                && dirty == 0 && timers.length == 1 && BookRunService.hasUnsettledOutcome(),
            "completed credits waits for the existing pending reward commit");
        BookComicService.handle("finish", story);
        BookComicService.handle("finish", credits);
        BookRunService.reconcileOutcome(); BookRunService.reconcileOutcome();
        check(requests.length == 2 && originalRun.outcome == "active" && dirty == 0,
            "late final packets and repeated reconcile never bypass the pending barrier");
        rewardPending = false;
        var queued:Number = timers.length;
        for (var i:Number = 0; i < queued; i++) timers[i]();
        check(originalRun.outcome == "victory" && dirty == 1 && api._ending == null
                && !BookRunService.hasUnsettledOutcome(),
            "released barrier persists the existing book outcome exactly once");
        check(_root._saveExt.bookRun === originalRun && originalRun.slot == "bookrun_cf6bookrun_fixture"
                && originalRun.bookId == "cf6-sting" && originalRun.routeId == "historical"
                && originalRun.seed == 17 && originalRun.planSeed == 17 && originalRun.startedAt == 100
                && _root.技能点数 == 41,
            "outcome persistence preserves temporary run identity and external SP");
        BookRunService.reconcileOutcome();
        BookComicService.handle("finish", story);
        BookComicService.handle("finish", credits);
        check(dirty == 1 && originalRun.outcome == "victory" && requests.length == 2,
            "settled ending and late callbacks cannot settle twice");
    }
    private static function testFinalInterruptionRecovery():Void {
        setup("cf6-sting");
        var api:Object = BookRunService;
        BookRunService.finish("victory");
        var closed:Object = latestPacket();
        BookComicService.handle("prepared", closed);
        closed.reason = "closed";
        BookComicService.handle("finish", closed);
        var ending:Object = api._ending;
        check(ending.storyRetry === true && ending.storyCompleted !== true
                && timers.length == 1 && _root._saveExt.bookRun.outcome == "active" && dirty == 0,
            "closed s7 retains one retry and no victory settlement");
        BookRunService.reconcileOutcome(); BookRunService.reconcileOutcome();
        BookComicService.handle("finish", closed);
        check(timers.length == 1 && requests.length == 1,
            "reconcile and late close cannot multiply the scheduled retry");
        timers[0]();
        check(requests.length == 2 && requests[1].pageId == "cf6-s7"
                && ending.storyActive === true && ending.storyRetry === false,
            "the scheduled recovery reopens s7 through the real service");
        var failed:Object = latestPacket();
        BookComicService.handle("prepared", failed);
        failed.reason = "failed";
        BookComicService.handle("finish", failed);
        check(timers.length == 2 && requests.length == 2
                && _root._saveExt.bookRun.outcome == "active" && dirty == 0,
            "failed replacement remains unsettled with one new retry");
        timers[1]();
        finishFinalSegments();
        check(requests.length == 4 && requests[2].pageId == "cf6-s7"
                && requests[3].pageId == "cf6-end"
                && _root._saveExt.bookRun.outcome == "victory" && dirty == 1 && api._ending == null,
            "failed and closed presentations recover to one complete final outcome");
    }
    private static function testFinalRejectsNewWorldWhilePending():Void {
        setup("cf6-sting");
        rewardPending = true;
        var api:Object = BookRunService;
        BookRunService.finish("victory");
        finishFinalSegments();
        check(api._ending.storyCompleted === true && timers.length == 1
                && _root._saveExt.bookRun.outcome == "active" && dirty == 0,
            "fixture reaches credits completion behind the pending reward barrier");
        replaceWorld();
        BookRunService.reconcileOutcome();
        check(api._ending == null && timers.length == 1
                && _root._saveExt.bookRun.outcome == "active" && dirty == 0 && rewardPending,
            "old world ending is rejected without clearing or replaying the pending reward");
        rewardPending = false;
        timers[0]();
        check(_root._saveExt.bookRun.outcome == "active" && dirty == 0,
            "releasing the lock cannot revive the rejected old-world outcome");
    }
    private static function testNonCf6FinishPaths():Void {
        var api:Object = BookRunService;
        setup("repair-campus");
        var campusRun:Object = _root._saveExt.bookRun;
        BookRunService.finish("victory");
        check(requests.length == 0 && campusRun.outcome == "victory" && dirty == 1
                && api._ending == null && _root.技能点数 == 41,
            "campus finish bypasses the CF6 story gate and keeps its existing outcome path");
        setup("lee-trial");
        var leeRun:Object = _root._saveExt.bookRun;
        BookRunService.finish("failure");
        check(requests.length == 0 && leeRun.outcome == "failure" && dirty == 1
                && telemetryCalls.length == 1 && telemetryCalls[0] == "failure"
                && api._ending == null,
            "Lee finish keeps telemetry and direct outcome persistence without CF6 comics");
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var keys:Array = ["gameworld", "server", "savePath", "_saveExt", "暂停", "当前关卡名",
            "淡出动画", "场景转换中", "帧计时器", "存档系统", "技能点数"];
        var saved:Object = {};
        for (var i:Number = 0; i < keys.length; i++) saved[keys[i]] = _root[keys[i]];
        var api:Object = BookRunService;
        var comic:Object = BookComicService;
        var clock:Object = BookRunClock;
        var definitionApi:Object = BookDefinition;
        var lee:Object = LeeTrialDefinition;
        var mapApi:Object = Cf6MapMechanism;
        var bossApi:Object = Cf6BossEncounter;
        var telemetry:Object = LeeTrialTelemetry;
        var saveManager:Object = SaveManager.getInstance();
        var oldChapter:Object = api._chapter, oldEnding:Object = api._ending;
        var oldChapterWatch:Object = api._chapterWatch;
        var oldChapterHandler:Function = oldChapterWatch == null ? null : oldChapterWatch.onEnterFrame;
        var oldPlanOwner:Object = api._cf6PlanOwner, oldPlans:Object = api._cf6BossPlans;
        var oldClockSession:Object = clock._session, oldClockWatch:Object = clock._watch;
        var oldClockHandler:Function = oldClockWatch == null ? null : oldClockWatch.onEnterFrame;
        var oldCf6:Object = definitionApi._cf6, oldLee:Object = lee._data;
        var oldBeginRoom:Function = mapApi.beginRoom, oldBossStart:Function = bossApi.start;
        var oldDialogue:Function = api.showChapterDialogue, oldTelemetry:Function = telemetry.finish;
        var oldPending:Function = saveManager.hasRewardCommitPending;
        var audio:Object = AudioBridge;
        var oldAudioTransport:Object = audio._sm;
        _root.gameworld = undefined;
        BookComicService.install(); BookRunService.install();
        mapApi.beginRoom = function(world:MovieClip, identity:Object, mapId:String, config:Object):Boolean {
            org.flashNight.arki.scene.Cf6BookRunStoryTest.roomCalls.push(
                {world:world, owner:identity, mapId:mapId, config:config});
            return true;
        };
        bossApi.start = function(world:MovieClip, identity:Object, plan:Object):Void {
            org.flashNight.arki.scene.Cf6BookRunStoryTest.bossCalls.push(
                {world:world, owner:identity, plan:plan});
        };
        api.showChapterDialogue = function(index:Number, owner:Object, slot:String):Void {
            org.flashNight.arki.scene.Cf6BookRunStoryTest.dialogueCalls.push(
                {index:index, owner:owner, slot:slot});
        };
        telemetry.finish = function(outcome:String):Void {
            org.flashNight.arki.scene.Cf6BookRunStoryTest.telemetryCalls.push(outcome);
        };
        saveManager.hasRewardCommitPending = function():Boolean {
            return org.flashNight.arki.scene.Cf6BookRunStoryTest.rewardPending;
        };
        try {
            testChapterPreparedHandoff();
            testChapterRejectsStaleContinuation();
            testFinalPendingBarrier();
            testFinalInterruptionRecovery();
            testFinalRejectsNewWorldWhilePending();
            testNonCf6FinishPaths();
        } finally {
            BookComicService.onTransportDisconnected();
            if (comic._watch != null) delete comic._watch.onEnterFrame;
            AudioBridge._resetForTests();
            AudioBridge._setTransportForTests(oldAudioTransport);
            mapApi.beginRoom = oldBeginRoom; bossApi.start = oldBossStart;
            api.showChapterDialogue = oldDialogue; telemetry.finish = oldTelemetry;
            saveManager.hasRewardCommitPending = oldPending;
            api._chapter = oldChapter; api._ending = oldEnding;
            api._cf6PlanOwner = oldPlanOwner; api._cf6BossPlans = oldPlans;
            api._chapterWatch = oldChapterWatch;
            if (oldChapterWatch != null) {
                if (oldChapterHandler != null) oldChapterWatch.onEnterFrame = oldChapterHandler;
                else delete oldChapterWatch.onEnterFrame;
            }
            clock._session = oldClockSession; clock._watch = oldClockWatch;
            if (oldClockWatch != null) {
                if (oldClockHandler != null) oldClockWatch.onEnterFrame = oldClockHandler;
                else delete oldClockWatch.onEnterFrame;
            }
            definitionApi._cf6 = oldCf6; lee._data = oldLee;
            if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
            for (i = 0; i < keys.length; i++) _root[keys[i]] = saved[keys[i]];
        }
        trace("Cf6BookRunStoryTest Tests Passed: " + passed);
        trace("Cf6BookRunStoryTest Tests Failed: " + failed);
    }
}
