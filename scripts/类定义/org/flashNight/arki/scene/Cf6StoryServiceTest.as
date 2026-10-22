import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.arki.audio.AudioBridge;
import org.flashNight.neur.Event.EventBus;

/** CF6 薄路由复用唯一漫画协议；不读写物理存档。 */
class org.flashNight.arki.scene.Cf6StoryServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var AUDIO_SESSION:String = "01234567-89ab-4cde-8f01-23456789abcd";
    private static var AUDIO_DIGEST:String =
        "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] Cf6Story: " + message); }
    }
    private static function setup():Void {
        var runService:Object = BookRunService;
        runService._chapter = null; runService._ending = null;
        if (runService._chapterWatch != null) delete runService._chapterWatch.onEnterFrame;
        BookComicService.onTransportDisconnected();
        if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("cf6StoryFixtureWorld", 9289);
        _root.savePath = "bookrun_cf6story_fixture";
        _root.当前关卡名 = "书中历险-毒刺行动";
        _root._saveExt = {bookRun:{slot:_root.savePath,bookId:"cf6-sting",routeId:"historical",
            seed:17,planSeed:17,startedAt:100,outcome:"active"}};
        var definition:Object = BookDefinition;
        definition._cf6 = {stageName:"书中历险-毒刺行动", maps:[
            {id:"TUTORIAL",dialogue:[],mechanism:{assetScale:1,layers:[]}},
            {id:"A01",dialogue:[],mechanism:{assetScale:1,layers:[]}},
            {id:"A02",dialogue:[],mechanism:{assetScale:1,layers:[]}}]};
        var clock:Object = BookRunClock; clock._session = null;
        if (clock._watch != null) delete clock._watch.onEnterFrame;
        _root.淡出动画 = {__returnFadeActive:false}; _root.场景转换中 = false;
        _root.__cf6Continues = 0; _root.__cf6Sends = []; _root.__cf6Request = null; _root.__cf6Requests = [];
        _root.__cf6Interrupted = 0; _root.__cf6InterruptionReason = ""; _root.__cf6ServerMode = "manual";
        _root.__cf6Timers = []; _root.__cf6Dirty = 0; _root.__cf6RoomDialogues = 0;
        _root.__cf6AudioMode = "sync"; _root.__cf6AudioTasks = [];
        _root.帧计时器 = {添加单次任务:function(callback:Function, delay:Number):Void {_root.__cf6Timers.push(callback)}};
        _root.存档系统 = {markDirty:function():Void {_root.__cf6Dirty++}};
        _root.server = {isSocketConnected:true,
            sendTaskWithCallback:function(task:String, p:Object, extra:Object, cb:Function):Void {
                _root.__cf6Request = p.initData; _root.__cf6Requests.push(p.initData); _root.__cf6Ack = cb;
                if (_root.__cf6ServerMode == "reject") {
                    cb({success:false,accepted:false,panel:"book-comic",presentationId:p.initData.presentationId});
                } else if (_root.__cf6ServerMode == "expire") {
                    BookComicService.onTransportDisconnected();
                } else if (_root.__cf6ServerMode == "complete") {
                    BookComicService.handle("finish", {v:1,callId:_root.__cf6Requests.length,
                        presentationId:p.initData.presentationId,slot:p.initData.slot,sceneId:p.initData.sceneId,
                        pageId:p.initData.pageId,panelInstanceId:"cf6.sync." + p.initData.presentationId,reason:"continue"});
                }
            },
            sendTaskToNode:function(task:String, payload:Object):Boolean {
                _root.__cf6Sends.push(payload); return true;
            }};
        var audioTransport:Object = {isSocketConnected:true};
        audioTransport.sendTaskToNode = function(task:String, payload:Object, extra:Object):Boolean {
            if (_root.__cf6AudioMode == "reject") return false;
            var request:Object = {};
            for (var key:String in payload) {
                if (Object.prototype.hasOwnProperty.call(payload, key)) request[key] = payload[key];
            }
            _root.__cf6AudioTasks.push(request);
            var acquire:Boolean = request.requestId.substr(
                request.requestId.length - 8) == ".acquire";
            if (_root.__cf6AudioMode == "sync"
                    || (_root.__cf6AudioMode == "failed" && acquire)) {
                var failedAcquire:Boolean = _root.__cf6AudioMode == "failed" && acquire;
                AudioBridge.handleBgmResult(audioResult(request,
                    failedAcquire ? "failed" : "started", failedAcquire ? "not_ready" : "ok"));
            } else if (_root.__cf6AudioMode == "deferred" && acquire) {
                AudioBridge.handleBgmResult(audioResult(request, "accepted_deferred", "ok"));
            }
            return true;
        };
        _root.__cf6AudioTransport = audioTransport;
        AudioBridge._resetForTests();
        AudioBridge._setTransportForTests(audioTransport);
        AudioBridge.handleAudioReady({task:"audio_ready",wireRevision:2,
            audioSessionId:AUDIO_SESSION,audioReadyGeneration:"42",deviceGeneration:"9",
            loaded:0,failed:0,overrides:0,capabilityDigest:AUDIO_DIGEST});
        PauseManager.set(false, "manual");
    }
    private static function audioResult(
            request:Object, completionState:String, category:String):Object {
        return {wireRevision:2,requestId:request.requestId,
            audioSessionId:request.audioSessionId,
            audioReadyGeneration:request.audioReadyGeneration,deviceGeneration:"9",
            operation:request.operation,completionState:completionState,category:category,
            stage:completionState == "accepted_deferred" ? "admission" : "native_start",
            nativeCode:0,hresult:0,
            decoderBackend:completionState == "accepted_deferred" ? "none" : "builtin",
            messageKey:"audio.bgm.result"};
    }
    private static function completeAudio(
            index:Number, completionState:String, category:String):Boolean {
        return AudioBridge.handleBgmResult(audioResult(
            _root.__cf6AudioTasks[index], completionState, category));
    }
    private static function audioCount(suffix:String):Number {
        var count:Number = 0;
        for (var i:Number = 0; i < _root.__cf6AudioTasks.length; i++) {
            var requestId:String = _root.__cf6AudioTasks[i].requestId;
            if (requestId.substr(requestId.length - suffix.length) == suffix) count++;
        }
        return count;
    }
    private static function follow():Void { _root.__cf6Continues++; }
    private static function interrupted(reason:String, phase:String):Void {
        _root.__cf6Interrupted++; _root.__cf6InterruptionReason = reason;
    }
    private static function packet():Object {
        var p:Object = _root.__cf6Request;
        return {v:1,callId:9,presentationId:p.presentationId,slot:p.slot,sceneId:p.sceneId,
            pageId:p.pageId,panelInstanceId:"cf6.fixture." + p.presentationId,reason:"continue"};
    }
    private static function open(page:String):Object {
        Cf6StoryService.begin(page, follow);
        return packet();
    }
    private static function last():Object { return _root.__cf6Sends[_root.__cf6Sends.length - 1]; }
    private static function testRoutes():Void {
        check(Cf6StoryService.knownPage("cf6-s1") && Cf6StoryService.knownPage("cf6-s7")
            && Cf6StoryService.knownPage("cf6-end"), "all seven stories and credits are known");
        check(!Cf6StoryService.knownPage("prologue") && !Cf6StoryService.knownPage("cf6-s8"),
            "foreign or invented pages are rejected");
        check(Cf6StoryService.pagesBeforeChapter(1).join(",") == "cf6-s1"
            && Cf6StoryService.pagesBeforeChapter(2).join(",") == "cf6-s2"
            && Cf6StoryService.pagesBeforeChapter(3).join(",") == "cf6-s3",
            "s1-s3 precede A01-A03");
        check(Cf6StoryService.pagesBeforeChapter(7).join(",") == "cf6-s4,cf6-s5"
            && Cf6StoryService.pagesBeforeChapter(17).join(",") == "cf6-s6",
            "vehicle-skipping adaptation keeps s4/s5 order and s6 precedes A18");
        check(!Cf6StoryService.hasChapterStory(0) && !Cf6StoryService.hasChapterStory(20),
            "tutorial and A22 have no duplicate in-room comic");
    }
    private static function testCloneAndLifecycle():Void {
        setup(); var p:Object = open("cf6-s1");
        check(_root.__cf6Request.presentationId.indexOf("bookcomic:") == 0 && _root.暂停 === true,
            "thin adapter uses the shared presentation counter and pause");
        _root._saveExt.bookRun = org.flashNight.gesh.object.PersistedSnapshot.clone(_root._saveExt.bookRun);
        BookComicService.handle("prepared", p);
        BookComicService.handle("finish", p);
        check(last().phase == "finished" && _root.__cf6Continues == 1 && _root.暂停 === false,
            "RewardStash-style clone retains identity and finishes once");
        BookComicService.handle("finish", p);
        check(_root.__cf6Continues == 1, "duplicate completion cannot advance twice");

        setup(); p = open("cf6-s2"); p.reason = "closed";
        BookComicService.handle("finish", p);
        check(last().phase == "finished" && _root.__cf6Continues == 0 && _root.暂停 === false,
            "closing the current CF6 panel never starts the next room");
        BookComicService.handle("prepared", p);
        check(_root.__cf6Continues == 0, "late preparation cannot reopen a closed sequence");

        setup(); p = open("cf6-s3"); p.reason = "failed";
        BookComicService.handle("finish", p);
        check(last().phase == "expired" && _root.__cf6Continues == 0 && _root.暂停 === false,
            "load failure does not fabricate completion");

        setup(); p = open("cf6-s4"); var late:Function = _root.__cf6Ack;
        _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("cf6StoryFixtureWorld", 9289);
        BookComicService.tick();
        check(last().callId == 0 && last().phase == "expired" && _root.__cf6Continues == 0,
            "same-path world rebuild expires without advancing");
        late({success:true,accepted:true,panel:"book-comic",presentationId:p.presentationId});
        BookComicService.handle("finish", p);
        check(_root.__cf6Continues == 0, "late admission and finish stay retired");

        setup(); p = open("cf6-s6");
        EventBus.getInstance().publish("SceneChanged");
        check(last().phase == "expired" && _root.__cf6Continues == 0 && _root.暂停 === false,
            "scene teardown cannot continue a CF6 sequence");

        setup(); p = open("cf6-s1");
        _root.__cf6Ack({success:false,error:"open failed"});
        check(last().phase == "expired" && _root.__cf6Continues == 0 && _root.暂停 === false,
            "admission failure releases pause without advancing");

        setup(); p = open("cf6-s7");
        var service:Object = BookComicService;
        service._active.began = getTimer() - 30001;
        BookComicService.tick();
        check(last().error == "prepare_timeout" && _root.__cf6Continues == 0,
            "preparation timeout cannot fabricate victory");

        setup(); p = open("cf6-s7");
        BookComicService.onTransportDisconnected(); BookComicService.onTransportDisconnected();
        check(_root.__cf6Continues == 0 && _root.暂停 === false,
            "disconnect resolves only its own pause and never completes the story");
    }
    private static function testSequences():Void {
        setup(); Cf6StoryService.beginChapter(7, follow);
        var first:Object = packet();
        check(first.pageId == "cf6-s4", "A06 completion opens s4 before A08");
        BookComicService.handle("finish", first);
        var second:Object = packet();
        check(second.pageId == "cf6-s5" && second.presentationId != first.presentationId
            && _root.__cf6Continues == 0 && _root.暂停 === true,
            "s4 continues to s5 through the same service without starting A08");
        second.reason = "skip"; BookComicService.handle("finish", second);
        check(_root.__cf6Continues == 1 && _root.暂停 === false,
            "skipping s5 completes the two-page route exactly once");
        BookComicService.handle("finish", first); BookComicService.handle("finish", second);
        check(_root.__cf6Continues == 1, "late sequence packets cannot repeat room continuation");

        setup(); Cf6StoryService.beginFinal(follow);
        var story:Object = packet(); story.reason = "skip";
        BookComicService.handle("finish", story);
        var credits:Object = packet();
        check(credits.pageId == "cf6-end" && _root.__cf6Continues == 0,
            "original space skip moves from s7 to credits, not directly to victory");
        BookComicService.handle("finish", credits);
        check(_root.__cf6Continues == 1, "credits return to the existing victory continuation once");
        BookComicService.handle("finish", story); BookComicService.handle("finish", credits);
        check(_root.__cf6Continues == 1, "duplicate final packets cannot duplicate victory");

        setup(); Cf6StoryService.beginFinal(follow);
        var cancelled:Object = packet(); cancelled.reason = "closed";
        BookComicService.handle("finish", cancelled);
        check(_root.__cf6Continues == 0 && _root.__cf6Request.pageId == "cf6-s7",
            "cancelling s7 neither opens credits nor persists victory");
    }
    private static function testInterruption():Void {
        setup(); Cf6StoryService.beginFinal(follow, interrupted);
        var p:Object = packet(); p.reason = "closed";
        BookComicService.handle("finish", p); BookComicService.onTransportDisconnected();
        check(_root.__cf6Interrupted == 1 && _root.__cf6InterruptionReason == "closed"
            && _root.__cf6Continues == 0 && _root.__cf6Request.pageId == "cf6-s7",
            "cancel reports one interruption without opening credits or completing victory");

        setup(); Cf6StoryService.beginChapter(7, follow, interrupted);
        p = packet(); _root.server.isSocketConnected = false;
        BookComicService.handle("finish", p);
        check(_root.__cf6Interrupted == 1 && _root.__cf6InterruptionReason == "open_failed"
            && _root.__cf6Continues == 0 && _root.__cf6Request.pageId == "cf6-s4",
            "a sequence boundary transport failure cannot skip s5 or start A08");

        setup(); Cf6StoryService.begin("cf6-s2", follow, interrupted);
        p = packet(); EventBus.getInstance().publish("SceneChanged");
        check(_root.__cf6Interrupted == 1 && _root.__cf6InterruptionReason == "scene_changed"
            && _root.__cf6Continues == 0,
            "scene expiry interrupts the owner without turning into completion");
    }
    private static function testBgmLeaseLifecycle():Void {
        setup();
        var p:Object = open("cf6-s1");
        check(audioCount(".acquire") == 1 && audioCount(".release") == 0,
            "synchronous acquire completes before open without losing its request identity");
        BookComicService.handle("prepared", p);
        check(last().phase == "presenting" && last().error == "",
            "synchronous final acquire admits ordinary comic music");
        BookComicService.handle("finish", p);
        BookComicService.handle("finish", p);
        check(audioCount(".release") == 1 && _root.__cf6Continues == 1,
            "continue releases exactly once despite a duplicate terminal packet");

        setup(); _root.__cf6AudioMode = "manual"; p = open("cf6-s2");
        var repeated:Object = packet(); repeated.callId = 10;
        BookComicService.handle("prepared", p);
        BookComicService.handle("prepared", repeated);
        check(_root.__cf6Sends.length == 0,
            "prepared waits instead of treating an unconfirmed acquire as silence");
        check(completeAudio(0, "accepted_deferred", "ok") && _root.__cf6Sends.length == 0,
            "accepted_deferred alone does not acquire the lease");
        check(completeAudio(0, "started", "ok") && _root.__cf6Sends.length == 2
                && _root.__cf6Sends[0].callId == 9 && _root.__cf6Sends[1].callId == 10
                && _root.__cf6Sends[0].error == "" && _root.__cf6Sends[1].error == "",
            "final acquire completes every pending prepared call without a timeout");
        BookComicService.handle("finish", p);
        check(audioCount(".acquire") == 1 && audioCount(".release") == 1,
            "deferred acquire still has one owner and one release");

        setup(); _root.__cf6AudioMode = "deferred"; p = open("cf6-s3");
        BookComicService.handle("prepared", p);
        check(_root.__cf6Sends.length == 0,
            "transport-driven deferred admission holds the prepared response");
        completeAudio(0, "started", "ok");
        check(last().phase == "presenting" && last().error == "",
            "transport-driven terminal result releases the prepared gate");
        BookComicService.handle("finish", p);

        setup(); _root.__cf6AudioMode = "manual"; p = open("cf6-s4");
        repeated = packet(); repeated.callId = 10;
        BookComicService.handle("prepared", p);
        BookComicService.handle("prepared", repeated);
        var service:Object = BookComicService;
        service._active.began = getTimer() - 2001;
        BookComicService.tick();
        check(_root.__cf6Sends.length == 2
                && _root.__cf6Sends[0].callId == 9 && _root.__cf6Sends[1].callId == 10
                && _root.__cf6Sends[0].error == "bgm_lease_unavailable"
                && _root.__cf6Sends[1].error == "bgm_lease_unavailable",
            "two-second timeout completes every pending prepared call with the same degradation");
        completeAudio(0, "started", "ok");
        check(_root.__cf6Sends.length == 2,
            "late acquire cannot fabricate another prepared response or claimed capability");
        BookComicService.handle("finish", p);
        check(audioCount(".release") == 1,
            "timed-out owner still releases a late-arriving lease exactly once");

        setup(); _root.__cf6AudioMode = "failed"; p = open("cf6-s5");
        BookComicService.handle("prepared", p);
        check(last().error == "bgm_lease_unavailable",
            "terminal acquire failure degrades instead of claiming silence");
        BookComicService.handle("finish", p);
        check(audioCount(".release") == 1,
            "failed acquire identity is released through the harmless owner no-op");

        setup(); _root.__cf6AudioMode = "reject"; p = open("cf6-s6");
        BookComicService.handle("prepared", p);
        check(last().error == "bgm_lease_unavailable" && audioCount(".acquire") == 0,
            "synchronous send rejection has no fake acquired capability");
        BookComicService.handle("finish", p);
        check(audioCount(".release") == 0 && _root.__cf6Continues == 1,
            "an acquire never sent needs no release and does not block continuation");

        var reasons:Array = ["continue", "skip", "closed", "failed"];
        for (var i:Number = 0; i < reasons.length; i++) {
            setup(); Cf6StoryService.begin("cf6-s1", follow, interrupted);
            p = packet(); p.reason = reasons[i];
            BookComicService.handle("finish", p);
            BookComicService.handle("finish", p);
            check(audioCount(".acquire") == 1 && audioCount(".release") == 1
                    && _root.__cf6Continues == (i < 2 ? 1 : 0)
                    && _root.__cf6Interrupted == (i < 2 ? 0 : 1),
                "terminal " + reasons[i] + " releases one sequence lease");
        }

        setup(); Cf6StoryService.begin("cf6-s2", follow, interrupted); p = packet();
        EventBus.getInstance().publish("SceneChanged");
        BookComicService.onTransportDisconnected();
        check(audioCount(".release") == 1 && _root.__cf6InterruptionReason == "scene_changed",
            "scene_changed releases once and later disconnect cannot repeat it");

        setup(); Cf6StoryService.begin("cf6-s3", follow, interrupted); p = packet();
        _root.__cf6Ack({success:false,accepted:false,panel:"book-comic",
            presentationId:p.presentationId});
        BookComicService.handle("finish", p);
        check(audioCount(".release") == 1 && _root.__cf6InterruptionReason == "open_failed",
            "open_failed and its late packet release only once");

        setup(); Cf6StoryService.beginChapter(7, follow, interrupted);
        var first:Object = packet();
        BookComicService.handle("finish", first);
        var second:Object = packet();
        check(audioCount(".acquire") == 1 && audioCount(".release") == 0,
            "s4 to s5 keeps one lease without an intermediate resume");
        second.reason = "skip"; BookComicService.handle("finish", second);
        check(audioCount(".release") == 1 && _root.__cf6Continues == 1,
            "s5 terminal skip releases the shared sequence lease");

        setup(); Cf6StoryService.beginFinal(follow, interrupted);
        var story:Object = packet(); story.reason = "skip";
        BookComicService.handle("finish", story);
        var credits:Object = packet();
        check(audioCount(".acquire") == 1 && audioCount(".release") == 0,
            "s7 to credits keeps the same lease without an intermediate resume");
        BookComicService.handle("finish", credits);
        check(audioCount(".release") == 1 && _root.__cf6Continues == 1,
            "credits continuation releases the final sequence lease");

        setup(); Cf6StoryService.begin("cf6-s1", follow, interrupted);
        var oldPacket:Object = packet(); oldPacket.reason = "closed";
        BookComicService.handle("finish", oldPacket);
        Cf6StoryService.begin("cf6-s2", follow, interrupted);
        var newPacket:Object = packet();
        BookComicService.handle("finish", oldPacket);
        check(audioCount(".acquire") == 2 && audioCount(".release") == 1,
            "late old-page failure cannot release the replacement owner");
        newPacket.reason = "closed"; BookComicService.handle("finish", newPacket);
        check(audioCount(".release") == 2,
            "replacement owner releases only its own lease");
    }
    private static function testPreparedSequences():Void {
        setup(); Cf6StoryService.beginChapter(7, follow, interrupted);
        var service:Object = BookComicService;
        var first:Object = packet();
        var firstSession:Object = service._active;
        BookComicService.handle("prepared", first);
        check(last().operation == "prepared" && last().callId == 9
                && last().presentationId == first.presentationId && last().phase == "presenting"
                && last().error == "" && service._active.phase == "presenting",
            "s4 real prepared response enters presenting after the synchronous lease");
        BookComicService.handle("finish", first);
        var second:Object = packet(); second.callId = 10;
        check(second.pageId == "cf6-s5" && second.presentationId != first.presentationId
                && service._active !== firstSession && service._active.phase == "opening",
            "s4 continuation creates a fresh s5 session and presentation identity");
        check(audioCount(".acquire") == 1 && audioCount(".release") == 0
                && _root.__cf6AudioTasks.length == 1 && _root.__cf6Continues == 0,
            "s4 to s5 has no intermediate BGM resume or room continuation");
        BookComicService.handle("prepared", second);
        check(last().operation == "prepared" && last().callId == 10
                && last().presentationId == second.presentationId && last().phase == "presenting"
                && last().error == "" && service._active.phase == "presenting",
            "s5 drains its own prepared packet instead of reusing the retired s4 reply");
        BookComicService.handle("finish", second);
        check(_root.__cf6Continues == 1 && _root.__cf6Interrupted == 0
                && audioCount(".acquire") == 1 && audioCount(".release") == 1
                && _root.__cf6AudioTasks.length == 2,
            "s5 alone reaches the final continuation and releases the shared lease once");

        setup(); Cf6StoryService.beginFinal(follow, interrupted);
        var story:Object = packet();
        var storySession:Object = service._active;
        BookComicService.handle("prepared", story);
        check(last().callId == 9 && last().presentationId == story.presentationId
                && last().phase == "presenting" && last().error == "",
            "s7 enters presenting through its real preparation branch");
        BookComicService.handle("finish", story);
        var credits:Object = packet(); credits.callId = 10;
        check(credits.pageId == "cf6-end" && credits.presentationId != story.presentationId
                && service._active !== storySession && audioCount(".release") == 0
                && _root.__cf6Continues == 0,
            "s7 continuation opens credits without skipping preparation or resuming BGM");
        BookComicService.handle("prepared", credits);
        check(last().callId == 10 && last().presentationId == credits.presentationId
                && last().phase == "presenting" && last().error == ""
                && service._active.phase == "presenting",
            "credits completes its own prepared handshake after s7");
        BookComicService.handle("finish", credits);
        check(_root.__cf6Continues == 1 && _root.__cf6Interrupted == 0
                && audioCount(".acquire") == 1 && audioCount(".release") == 1,
            "prepared s7 and credits produce one final continuation and one release");
    }
    private static function testPreparedSequenceDegradation():Void {
        setup(); _root.__cf6AudioMode = "failed";
        Cf6StoryService.beginChapter(7, follow, interrupted);
        var service:Object = BookComicService;
        var first:Object = packet();
        BookComicService.handle("prepared", first);
        check(last().callId == 9 && last().presentationId == first.presentationId
                && last().phase == "presenting" && last().error == "bgm_lease_unavailable",
            "failed lease gives s4 a bounded degraded preparation result");
        BookComicService.handle("finish", first);
        var second:Object = packet(); second.callId = 10;
        BookComicService.handle("prepared", second);
        check(last().callId == 10 && last().presentationId == second.presentationId
                && last().phase == "presenting" && last().error == "bgm_lease_unavailable"
                && _root.__cf6Sends.length == 3,
            "failed lease degrades s5 with the same error and no stale s4 reply");
        BookComicService.handle("finish", second);
        check(_root.__cf6Continues == 1 && _root.__cf6Interrupted == 0
                && audioCount(".acquire") == 1 && audioCount(".release") == 1,
            "two degraded segments still finish once with bounded lease cleanup");

        setup(); _root.__cf6AudioMode = "manual";
        Cf6StoryService.beginChapter(7, follow, interrupted);
        first = packet();
        BookComicService.handle("prepared", first);
        service._active.began = getTimer() - 2001;
        BookComicService.tick();
        check(last().callId == 9 && last().presentationId == first.presentationId
                && last().phase == "presenting" && last().error == "bgm_lease_unavailable",
            "lease timeout resolves the first pending segment with bounded degradation");
        BookComicService.handle("finish", first);
        second = packet(); second.callId = 10;
        BookComicService.handle("prepared", second);
        check(last().callId == 10 && last().presentationId == second.presentationId
                && last().phase == "presenting" && last().error == "bgm_lease_unavailable"
                && _root.__cf6Sends.length == 3,
            "the segment after timeout drains immediately without inheriting old pending");
        var sendsBeforeLate:Number = _root.__cf6Sends.length;
        completeAudio(0, "started", "ok");
        check(_root.__cf6Sends.length == sendsBeforeLate
                && last().presentationId == second.presentationId
                && last().error == "bgm_lease_unavailable",
            "late acquire cannot rewrite the second segment degradation or repeat its reply");
        BookComicService.handle("finish", second);
        check(_root.__cf6Continues == 1 && _root.__cf6Interrupted == 0
                && audioCount(".acquire") == 1 && audioCount(".release") == 1,
            "timeout followed by late acquire still has one continuation and one release");
    }
    private static function testPreparedLateBoundaries():Void {
        setup(); _root.__cf6AudioMode = "manual";
        Cf6StoryService.beginChapter(7, follow, interrupted);
        var service:Object = BookComicService;
        var oldPacket:Object = packet();
        BookComicService.handle("prepared", oldPacket);
        oldPacket.reason = "closed";
        BookComicService.handle("finish", oldPacket);
        check(_root.__cf6Interrupted == 1 && _root.__cf6Continues == 0
                && audioCount(".release") == 1,
            "closing with pending preparation retires the old owner and releases once");
        Cf6StoryService.begin("cf6-s2", follow, interrupted);
        var replacement:Object = packet(); replacement.callId = 20;
        var sendsBeforeLate:Number = _root.__cf6Sends.length;
        completeAudio(0, "started", "ok");
        check(_root.__cf6Sends.length == sendsBeforeLate
                && service._active.presentationId == replacement.presentationId
                && service._active.phase == "opening" && audioCount(".acquire") == 2
                && audioCount(".release") == 1,
            "late acquire after close cannot restart the old story or settle the replacement");
        BookComicService.handle("prepared", oldPacket);
        check(last().presentationId == oldPacket.presentationId && last().phase == "finished"
                && service._active.presentationId == replacement.presentationId
                && service._active.phase == "opening" && _root.__cf6Interrupted == 1
                && _root.__cf6Continues == 0 && audioCount(".release") == 1,
            "late old prepared only confirms its tombstone and cannot interrupt the new session");
        sendsBeforeLate = _root.__cf6Sends.length;
        BookComicService.handle("prepared", replacement);
        check(_root.__cf6Sends.length == sendsBeforeLate && service._active.phase == "opening",
            "replacement preparation remains pending on its own lease");
        completeAudio(2, "started", "ok");
        check(last().callId == 20 && last().presentationId == replacement.presentationId
                && last().phase == "presenting" && last().error == "",
            "only the replacement acquire resolves the replacement prepared packet");
        BookComicService.handle("finish", replacement);
        check(_root.__cf6Continues == 1 && _root.__cf6Interrupted == 1
                && audioCount(".acquire") == 2 && audioCount(".release") == 2,
            "old and replacement owners each release once without a late duplicate");
    }
    private static function testPreparedSynchronousReentrancy():Void {
        setup(); Cf6StoryService.beginChapter(7, follow, interrupted);
        var service:Object = BookComicService;
        var first:Object = packet();
        _root.server.sendTaskToNode = function(task:String, payload:Object):Boolean {
            _root.__cf6Sends.push(payload);
            if (payload.operation == "prepared" && payload.pageId == "cf6-s4") {
                BookComicService.handle("finish", {v:1,callId:payload.callId,
                    presentationId:payload.presentationId,slot:payload.slot,sceneId:payload.sceneId,
                    pageId:payload.pageId,panelInstanceId:payload.panelInstanceId,reason:"continue"});
            }
            return true;
        };
        BookComicService.handle("prepared", first);
        var second:Object = packet(); second.callId = 10;
        check(second.pageId == "cf6-s5" && service._active.phase == "opening"
                && _root.__cf6Sends.length == 2 && _root.__cf6Sends[0].phase == "presenting"
                && _root.__cf6Sends[1].phase == "finished" && audioCount(".release") == 0,
            "synchronous finish inside the first prepared response opens only the next segment");
        BookComicService.handle("prepared", second);
        check(last().callId == 10 && last().presentationId == second.presentationId
                && last().phase == "presenting" && last().error == "",
            "reentrant segment transition leaves a reusable empty prepared queue");
        BookComicService.handle("finish", second);
        check(_root.__cf6Continues == 1 && _root.__cf6Interrupted == 0
                && audioCount(".acquire") == 1 && audioCount(".release") == 1,
            "synchronous reentrancy still converges to one continuation and one release");
    }
    private static function testBookRunHandoff():Void {
        var api:Object = BookRunService;
        var comic:Object = BookComicService;
        var mapApi:Object = Cf6MapMechanism, bossApi:Object = Cf6BossEncounter;
        var originalDialogue:Function = api.showChapterDialogue;
        var originalBeginRoom:Function = mapApi.beginRoom, originalBossStart:Function = bossApi.start;
        api.showChapterDialogue = function(index:Number, owner:Object, slot:String):Void {_root.__cf6RoomDialogues++};
        mapApi.beginRoom = function(world:MovieClip, owner:Object, mapId:String, config:Object):Boolean {return true;};
        bossApi.start = function(world:MovieClip, owner:Object, plan:Object):Void {};
        try {
            setup(); _root.__cf6ServerMode = "reject"; BookRunService.playChapter(1);
            var chapter:Object = api._chapter;
            check(chapter != null && chapter.storyActive === false && chapter.started !== true && comic._active == null,
                "synchronous admission rejection cannot reactivate a retired chapter");
            check(typeof api._chapterWatch.onEnterFrame == "function" && _root.暂停 === false,
                "synchronous rejection leaves a retry watch and releases pause");
            _root.__cf6ServerMode = "manual"; BookRunService.presentChapter();
            var requestCount:Number = _root.__cf6Requests.length;
            var identity:Object = StageReturnFlow.worldIdentity(_root.gameworld);
            EventBus.getInstance().publish("SceneTransitionReleased", _root.gameworld, "", identity);
            BookRunService.presentChapter();
            check(_root.__cf6Requests.length == requestCount && chapter.storyActive === true && comic._active != null,
                "duplicate scene release cannot reopen an active chapter");

            setup(); _root.__cf6ServerMode = "expire"; BookRunService.playChapter(1);
            chapter = api._chapter;
            check(chapter != null && chapter.storyActive === false && chapter.started !== true && comic._active == null,
                "synchronous expiry cannot be overwritten by beginChapter returning true");
            check(typeof api._chapterWatch.onEnterFrame == "function" && _root._saveExt.bookRun.outcome == "active",
                "synchronous expiry remains retryable without completing the room");

            setup(); _root.__cf6ServerMode = "complete"; BookRunService.playChapter(1);
            chapter = api._chapter;
            check(chapter != null && chapter.started === true && chapter.storyActive === false
                && api._chapterWatch.onEnterFrame === undefined && _root.__cf6RoomDialogues == 1,
                "synchronous completion enters the room once without restoring storyActive");
            BookRunService.presentChapter();
            EventBus.getInstance().publish("SceneTransitionReleased", _root.gameworld, "", StageReturnFlow.worldIdentity(_root.gameworld));
            check(_root.__cf6RoomDialogues == 1 && _root.__cf6Requests.length == 1,
                "duplicate scene release after completion cannot restart the old room");

            setup(); BookRunService.playChapter(1);
            var oldChapter:Object = api._chapter, oldPacket:Object = packet();
            BookRunService.playChapter(2);
            var newChapter:Object = api._chapter, newWatch:Function = api._chapterWatch.onEnterFrame;
            BookComicService.handle("finish", oldPacket);
            check(oldChapter.started !== true && api._chapter === newChapter
                && api._chapterWatch.onEnterFrame === newWatch && _root.__cf6RoomDialogues == 0,
                "late old chapter continuation cannot delete the replacement watch or start its old room");
            BookRunService.presentChapter();
            check(newChapter.storyActive === true && _root.__cf6Request.pageId == "cf6-s2",
                "replacement chapter in the same world and run can still open after the late packet");

            setup(); _root.__cf6ServerMode = "reject"; BookRunService.finish("victory");
            var ending:Object = api._ending; requestCount = _root.__cf6Requests.length;
            check(ending != null && ending.storyActive === false && ending.storyRetry === true
                && _root._saveExt.bookRun.outcome == "active" && _root.__cf6Timers.length == 1,
                "synchronous ending rejection schedules retry instead of a permanently active ending");
            BookRunService.finish("victory");
            check(_root.__cf6Requests.length == requestCount && _root.__cf6Timers.length == 1,
                "duplicate ending arrival cannot open or schedule twice");

            setup(); _root.__cf6ServerMode = "expire"; BookRunService.finish("victory");
            ending = api._ending;
            check(ending != null && ending.storyActive === false && ending.storyRetry === true
                && ending.storyCompleted !== true && _root.__cf6Timers.length == 1,
                "synchronous ending expiry keeps victory unsettled and retryable");

            setup(); _root.__cf6ServerMode = "complete"; BookRunService.finish("victory");
            check(api._ending == null && _root._saveExt.bookRun.outcome == "victory" && _root.__cf6Dirty == 1
                && _root.__cf6Requests.length == 2 && _root.__cf6Requests[0].pageId == "cf6-s7"
                && _root.__cf6Requests[1].pageId == "cf6-end",
                "synchronous s7 and credits completion reaches the existing outcome barrier exactly once");
        } finally {
            api.showChapterDialogue = originalDialogue;
            mapApi.beginRoom = originalBeginRoom; bossApi.start = originalBossStart;
            api._chapter = null; api._ending = null;
            if (api._chapterWatch != null) delete api._chapterWatch.onEnterFrame;
        }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var keys:Array = ["gameworld","server","savePath","_saveExt","暂停","__cf6Continues",
            "__cf6Sends","__cf6Request","__cf6Requests","__cf6Ack","__cf6Interrupted","__cf6InterruptionReason","当前关卡名",
            "淡出动画","场景转换中","帧计时器","存档系统","__cf6ServerMode","__cf6Timers","__cf6Dirty","__cf6RoomDialogues",
            "__cf6AudioMode","__cf6AudioTasks","__cf6AudioTransport"];
        var saved:Object = {};
        for (var i:Number = 0; i < keys.length; i++) saved[keys[i]] = _root[keys[i]];
        var audio:Object = AudioBridge;
        var savedAudioTransport:Object = audio._sm;
        var definition:Object = BookDefinition, savedCf6:Object = definition._cf6;
        var clock:Object = BookRunClock, savedClockSession:Object = clock._session;
        var savedClockWatch:Object = clock._watch;
        var savedClockHandler:Function = savedClockWatch == null ? null : savedClockWatch.onEnterFrame;
        var saveManager:Object = org.flashNight.neur.Server.SaveManager.getInstance();
        var savedPending:Function = saveManager.hasRewardCommitPending;
        saveManager.hasRewardCommitPending = function():Boolean {return false;};
        _root.gameworld = undefined;
        BookComicService.install(); BookRunService.install();
        try { testRoutes(); testCloneAndLifecycle(); testSequences(); testInterruption(); testBgmLeaseLifecycle();
            testPreparedSequences(); testPreparedSequenceDegradation(); testPreparedLateBoundaries();
            testPreparedSynchronousReentrancy(); testBookRunHandoff(); }
        finally {
            var runService:Object = BookRunService;
            runService._chapter = null; runService._ending = null;
            if (runService._chapterWatch != null) delete runService._chapterWatch.onEnterFrame;
            BookComicService.onTransportDisconnected();
            var comic:Object = BookComicService;
            if (comic._watch != null) delete comic._watch.onEnterFrame;
            clock._session = savedClockSession; clock._watch = savedClockWatch;
            if (savedClockWatch != null) {
                if (savedClockHandler != null) savedClockWatch.onEnterFrame = savedClockHandler;
                else delete savedClockWatch.onEnterFrame;
            }
            definition._cf6 = savedCf6; saveManager.hasRewardCommitPending = savedPending;
            AudioBridge._resetForTests();
            AudioBridge._setTransportForTests(savedAudioTransport);
            _root.gameworld.removeMovieClip();
            for (i = 0; i < keys.length; i++) _root[keys[i]] = saved[keys[i]];
        }
        trace("Cf6StoryServiceTest Tests Passed: " + passed);
        trace("Cf6StoryServiceTest Tests Failed: " + failed);
    }
}
