import org.flashNight.arki.scene.*;
import org.flashNight.arki.pause.PauseManager;
import org.flashNight.neur.Event.EventBus;

/** 身份、暂停、晚到回包、精确一次续演与竞速暂停边界；不读写物理存档。 */
class org.flashNight.arki.scene.BookComicServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] BookComic: " + message); }
    }
    private static function setup():Void {
        BookComicService.onTransportDisconnected();
        if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("comicFixtureWorld", 9287);
        _root.savePath = "bookrun_comic_fixture";
        _root._saveExt = {bookRun:{slot:_root.savePath,bookId:"repair-campus",seed:17,startedAt:100,outcome:"active"}};
        _root.__comicContinues = 0; _root.__comicSends = [];
        _root.server = {isSocketConnected:true,
            sendTaskWithCallback:function(task:String, p:Object, extra:Object, cb:Function):Void {
                _root.__comicRequest = p.initData; _root.__comicAck = cb;
            },
            sendTaskToNode:function(task:String, payload:Object):Boolean {
                _root.__comicSends.push(payload); return true;
            }};
        PauseManager.set(false, "manual");
    }
    private static function follow():Void { _root.__comicContinues++; }
    private static function open(page:String):Object {
        BookComicService.begin(page, follow);
        var p:Object = _root.__comicRequest;
        return {v:1,callId:9,presentationId:p.presentationId,slot:p.slot,sceneId:p.sceneId,
            pageId:p.pageId,panelInstanceId:"comic.fixture." + p.presentationId,reason:"continue"};
    }
    private static function last():Object { return _root.__comicSends[_root.__comicSends.length - 1]; }
    private static function testLifecycle():Void {
        setup(); var p:Object = open("prologue");
        check(_root.暂停 === true, "opening owns a pause before web readiness");
        BookComicService.handle("prepared", p);
        check(last().success === true && last().phase == "presenting", "exact preparation becomes presenting");
        var foreign:Object = {v:1,callId:10,presentationId:p.presentationId,slot:p.slot,sceneId:p.sceneId,
            pageId:p.pageId,panelInstanceId:"foreign",reason:"continue"};
        BookComicService.handle("finish", foreign);
        check(last().success === false && _root.暂停 === true && _root.__comicContinues == 0,
            "foreign panel cannot finish or resume a bound presentation");
        var otherLease:String = PauseManager.lease(true, "native_dialogue_fixture");
        BookComicService.handle("finish", p);
        check(last().phase == "finished" && _root.__comicContinues == 1, "finish resumes once after authoritative response");
        check(_root.暂停 === true, "finish cannot release someone else's dialogue pause");
        BookComicService.handle("finish", p);
        check(last().phase == "finished" && _root.__comicContinues == 1, "lost finish response is idempotent");
        PauseManager.releaseLease(otherLease);
        check(_root.暂停 === false, "only the final owner releases effective pause");
        var p2:Object = open("boss");
        BookComicService.handle("prepared", p);
        check(last().phase == "finished" && _root.暂停 === true, "old ready cannot revive or unpause the next page");
        p2.reason = "skip"; BookComicService.handle("finish", p2);
        check(last().phase == "finished" && _root.__comicContinues == 2 && _root.暂停 === false,
            "skip before ready resolves the current opening exactly once");

        setup(); p = open("prologue"); var late:Function = _root.__comicAck;
        _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("comicFixtureWorld", 9287);
        BookComicService.tick();
        check(last().callId == 0 && last().phase == "expired" && _root.__comicContinues == 0,
            "same-path world replacement expires without advancing the new world");
        check(_root.暂停 === false, "world replacement releases only the old claim");
        late({success:true,accepted:true,panel:"book-comic",presentationId:p.presentationId});
        BookComicService.handle("prepared", p);
        check(last().phase == "expired" && _root.__comicContinues == 0, "late admission and ready cannot revive a retired world");

        setup(); p = open("boss");
        EventBus.getInstance().publish("SceneChanged");
        check(last().phase == "expired" && _root.__comicContinues == 0 && _root.暂停 === false,
            "scene teardown synchronously retires pending web presentation");

        setup(); p = open("prologue");
        _root.__comicAck({success:false,error:"open failed"});
        check(last().phase == "expired" && _root.__comicContinues == 1 && _root.暂停 === false,
            "admission failure resumes gameplay and leaves an exact tombstone");
        setup(); p = open("boss");
        var service:Object = BookComicService;
        service._active.began = getTimer() - 30001;
        BookComicService.tick();
        check(last().error == "prepare_timeout" && _root.__comicContinues == 1 && _root.暂停 === false,
            "unprepared panel times out without a permanent pause");
        BookComicService.handle("prepared", p);
        check(last().phase == "expired" && _root.__comicContinues == 1, "late ready after timeout stays retired");

        setup(); p = open("boss");
        _root.server.isSocketConnected = false;
        BookComicService.onTransportDisconnected(); BookComicService.onTransportDisconnected();
        check(_root.__comicContinues == 1 && _root.暂停 === false, "disconnect resolves once with no invisible claim");
        setup(); p = open("boss"); p.reason = "failed";
        BookComicService.handle("finish", p);
        check(last().phase == "expired" && _root.__comicContinues == 1 && _root.暂停 === false,
            "web image failure can retire before preparation");
        setup(); p = open("boss"); _root.savePath = "different_slot"; p.reason = "closed";
        BookComicService.handle("finish", p);
        check(last().phase == "expired" && _root.__comicContinues == 0,
            "closing a foreign save context never advances that save");
    }
    private static function testChapterWaitsForCurtain():Void {
        var transition:Object = org.flashNight.arki.ui.SceneTransitionService;
        var oldSend:Function = transition.sendOverride;
        var oldFade = _root.淡出动画, oldTransition = _root.场景转换中;
        var oldBackground = _root.加载背景列表;
        transition.sendOverride = function(packet:Object):Boolean { _root.__comicCurtain = packet; return true; };
        BookRunService.install();
        try {
            setup(); _root.__comicRequest = null; _root.加载背景列表 = null;
            _root.淡出动画 = {_currentframe:5, play:function():Void {}, stop:function():Void {}};
            transition.begin(_root.淡出动画);
            var packet:Object = _root.__comicCurtain;
            transition.presented({requestId:packet.requestId,revision:packet.revision,kind:"covered"});
            _root.gameworld.removeMovieClip();
            _root.gameworld = _root.createEmptyMovieClip("comicFixtureWorld",9287);
            _root.淡出动画._currentframe = 17; _root.淡出动画.__returnFadeActive = false; _root.场景转换中 = false;
            var identity:Object = StageReturnFlow.worldIdentity(_root.gameworld);
            EventBus.getInstance().publish("SceneReady",_root.gameworld,"",identity);
            BookRunService.playChapter(0); BookRunService.presentChapter();
            check(_root.__comicRequest == null && _root.暂停 === false,
                "chapter arrival cannot pause or open a comic before the loading curtain exits");
            _root.淡出动画._currentframe = 30; transition.awaitReveal(_root.淡出动画);
            packet = _root.__comicCurtain;
            transition.presented({requestId:packet.requestId,revision:packet.revision,kind:"revealed"});
            BookRunService.presentChapter();
            check(_root.__comicRequest == null && _root.暂停 === false,
                "reveal receipt alone is not permission to pause the final fade frames");
            _root.淡出动画._currentframe = 36; transition.clear();
            check(_root.__comicRequest.pageId == "prologue" && _root.暂停 === true,
                "actual released curtain hands off to the comic and pause once");
            var presentation:String = _root.__comicRequest.presentationId;
            EventBus.getInstance().publish("SceneTransitionReleased",_root.gameworld,"",identity);
            BookRunService.presentChapter();
            check(_root.__comicRequest.presentationId == presentation,
                "duplicate release cannot open another presentation");
            _root.savePath = "retired"; BookComicService.tick();
            setup(); _root.__comicRequest = null; _root.场景转换中 = true;
            BookRunService.playChapter(0);
            _root.gameworld.removeMovieClip();
            _root.gameworld = _root.createEmptyMovieClip("comicFixtureWorld",9287);
            _root.场景转换中 = false; BookRunService.presentChapter();
            check(_root.__comicRequest == null && _root.暂停 === false,
                "same-path replacement cannot inherit a delayed chapter");
            _root.场景转换中 = true; BookRunService.playChapter(0);
            _root.savePath = "different"; _root.场景转换中 = false; BookRunService.presentChapter();
            check(_root.__comicRequest == null && _root.暂停 === false,
                "save switch cancels a delayed chapter without starting another save's comic");
        } finally {
            transition.clear(); transition.sendOverride = oldSend;
            _root.淡出动画 = oldFade; _root.场景转换中 = oldTransition; _root.加载背景列表 = oldBackground;
        }
    }
    private static function testClock():Void {
        var state:Object = {last:1000,elapsed:0,paused:false};
        check(BookRunClock.accumulate(state, 3500, true) == 2500, "pause entry preserves exactly preceding play time");
        check(BookRunClock.accumulate(state, 903500, true) == 2500, "long comic reading costs zero race time");
        check(BookRunClock.accumulate(state, 950000, false) == 2500, "leaving dialogue does not bill the pause interval");
        check(BookRunClock.accumulate(state, 951200, false) == 3700, "active play resumes from the release edge");
        state = {last:0,elapsed:0,paused:false};
        BookRunClock.accumulate(state, 2000, true);
        BookRunClock.accumulate(state, 7000, true);
        BookRunClock.accumulate(state, 12000, false);
        check(BookRunClock.accumulate(state, 15000, false) == 5000, "overlapping claims count one union of pause time");
        check(BookRunClock.elapsed({clockVersion:1,playTimeMs:5000,startedAt:0}) == 5000,
            "settlement uses persisted play time rather than wall clock");
        setup(); BookRunClock.start(_root._saveExt.bookRun);
        var clock:Object = BookRunClock;
        clock._session.last = getTimer() - 1200;
        var lease:String = PauseManager.lease(true, "comic_clock_fixture");
        var before:Number = _root._saveExt.bookRun.playTimeMs;
        check(before >= 1200 && clock._session.paused === true, "real pause subscription samples before stopping");
        clock._session.last = getTimer() - 60000;
        BookRunClock.tick();
        check(_root._saveExt.bookRun.playTimeMs == before, "real root watcher does not bill paused minutes");
        PauseManager.releaseLease(lease);
        clock._session.last = getTimer() - 800;
        check(BookRunClock.elapsed(_root._saveExt.bookRun) >= before + 800,
            "settlement samples the final active interval after pause release");
        clock._session = null;
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var keys:Array = ["gameworld","server","savePath","_saveExt","暂停","__comicContinues",
            "__comicSends","__comicRequest","__comicAck"];
        var saved:Object = {};
        for (var i:Number = 0; i < keys.length; i++) saved[keys[i]] = _root[keys[i]];
        _root.gameworld = undefined;
        BookComicService.install();
        try { testLifecycle(); testClock(); testChapterWaitsForCurtain(); }
        finally {
            BookComicService.onTransportDisconnected();
            _root.gameworld.removeMovieClip();
            for (i = 0; i < keys.length; i++) _root[keys[i]] = saved[keys[i]];
        }
        trace("BookComicServiceTest Tests Passed: " + passed);
        trace("BookComicServiceTest Tests Failed: " + failed);
    }
}
