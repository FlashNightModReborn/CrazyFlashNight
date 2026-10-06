import org.flashNight.arki.ui.BookshelfPanelService;
import org.flashNight.arki.scene.StageReturnFlow;
import org.flashNight.gesh.object.PersistedSnapshot;
/** Real MovieClip identity and orchestration; storage is a controlled fixture, not SOL evidence. */
class org.flashNight.arki.ui.BookshelfPanelServiceTest {
    private static var passed:Number;
    private static var failed:Number;
    private static var fake:Object;
    private static function check(value:Boolean, message:String):Void {
        if (value) passed++; else { failed++; trace("[FAIL] Bookshelf: " + message); }
    }
    private static function setup():Void {
        BookshelfPanelService._resetForTests();
        if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        _root.gameworld = _root.createEmptyMovieClip("bookFixtureWorld", 9230);
        _root.savePath = "book_fixture_a"; _root.角色名 = "A"; _root.允许存档 = true;
        _root._saveExt = {}; _root.tasks_finished = {}; _root.tasks_finished[21] = 1;
        _root.场景转换中 = false; _root.技能点数 = 100;
        _root.__bookWire = ""; _root.__bookFades = 0; _root.__bookEntry = null;
        _root.__bookEffects = [];
        _root.server = {sendSocketMessage:function(message) { _root.__bookWire = message; return true; }};
        _root.淡出动画 = {淡出跳转帧:function(frame) { _root.__bookFrame = frame; _root.__bookFades++; return true; }};
        fake = {pending:false,fence:true,replacements:0};
        fake.hasRewardCommitPending = function() { return this.pending; };
        fake.rewardCommitOperationId = function() { return this.pending ? _root.__bookEntry.id : ""; };
        fake.resolveRewardCommit = function(id) {
            if (id !== _root.__bookEntry.id) return;
            this.pending = false;
            _root.__bookEntry.callback(true, _root.__bookEntry.domain);
        };
        fake.flushBeforeTransition = function(reason) { return this.fence; };
        fake.packGameState = function() { return {ext:_root._saveExt}; };
        fake.replacePlayerContext = function(slot, snapshot, run) {
            this.replacements++;
            _root.savePath = slot;
            _root._saveExt = run == null ? PersistedSnapshot.clone(snapshot.ext) : {bookRun:PersistedSnapshot.clone(run)};
            return true;
        };
    }
    private static function open():String {
        BookshelfPanelService.openPanel();
        return new LiteJSON().parse(_root.__bookWire).initData.token;
    }
    private static function pumpReturnJobs():Void {
        var jobs:Array = _root.__bookReturnJobs;
        _root.__bookReturnJobs = [];
        for (var i:Number = 0; i < jobs.length; i++) jobs[i]();
    }
    /** 真实过场权威 + SceneReady + 书架 opener；帧推进和调度队列受控，不写存档。 */
    private static function testReturnUiWaitsForCurtain():Void {
        var keys:Array = ["帧计时器", "当前为战斗地图", "_webPanelPauseLease", "加载背景列表",
            "__bookReturnJobs", "__bookReturnOpens", "__bookCurtain", "书中调试"];
        var saved:Object = {};
        for (var k:Number = 0; k < keys.length; k++) saved[keys[k]] = _root[keys[k]];
        var transitionClass:Object = org.flashNight.arki.ui.SceneTransitionService;
        var oldSend:Function = transitionClass.sendOverride;
        _root.帧计时器 = {添加单次任务:function(fn:Function, delay:Number):Void {
            _root.__bookReturnJobs.push(fn);
        }};
        transitionClass.sendOverride = function(packet:Object):Boolean {
            _root.__bookCurtain = packet; return true;
        };
        org.flashNight.arki.scene.BookRunService.install();
        try {
            var outcomes:Array = ["failure", "retreat", "victory"];
            for (var i:Number = 0; i < outcomes.length; i++) {
                setup();
                _root._saveExt.bookRun = {started:true, outcome:outcomes[i]};
                _root.当前为战斗地图 = false; _root._webPanelPauseLease = undefined;
                _root.加载背景列表 = null; _root.__bookReturnJobs = []; _root.__bookReturnOpens = 0;
                _root.server.sendSocketMessage = function(message:String):Boolean {
                    _root.__bookWire = message; _root.__bookReturnOpens++; return true;
                };
                var fade:Object = {_currentframe:5, play:function():Void {}, stop:function():Void {}};
                _root.淡出动画 = fade;
                org.flashNight.arki.ui.SceneTransitionService.begin(fade);
                var packet:Object = _root.__bookCurtain;
                org.flashNight.arki.ui.SceneTransitionService.presented({
                    requestId:packet.requestId, revision:packet.revision, kind:"covered"});
                // 正式第 17 帧会释放 admission 标记，但独立 Web 遮罩仍在等待目标帧。
                fade._currentframe = 17; fade.__returnFadeActive = false;
                _root.gameworld.removeMovieClip();
                _root.gameworld = _root.createEmptyMovieClip("bookFixtureWorld", 9230);
                var identity:Object = StageReturnFlow.worldIdentity(_root.gameworld);
                org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady", _root.gameworld, "", identity);
                org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady", _root.gameworld, "", identity);
                pumpReturnJobs();
                check(_root.__bookReturnOpens == 0 && org.flashNight.arki.ui.SceneTransitionService.isPresentationPending(),
                    outcomes[i] + ": SceneReady and frame-17 release cannot open the pausing bookshelf");
                fade._currentframe = 30;
                org.flashNight.arki.ui.SceneTransitionService.awaitReveal(fade);
                packet = _root.__bookCurtain;
                org.flashNight.arki.ui.SceneTransitionService.presented({
                    requestId:packet.requestId, revision:packet.revision, kind:"revealed"});
                pumpReturnJobs();
                check(packet.phase == "reveal" && _root.__bookReturnOpens == 0,
                    outcomes[i] + ": even accepted reveal waits for the real successful tail");
                fade._currentframe = 36;
                org.flashNight.arki.ui.SceneTransitionService.clear();
                pumpReturnJobs(); pumpReturnJobs();
                check(!org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()
                        && _root.__bookReturnOpens == 1 && new LiteJSON().parse(_root.__bookWire).panel == "bookshelf",
                    outcomes[i] + ": terminal curtain release opens the existing bookshelf once");
            }
            // 迟到的自动开窗仍受槽位及真实 MovieClip 的独立身份约束。
            _root.__bookReturnOpens = 0;
            org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady", _root.gameworld, "", identity);
            _root.savePath = "book_fixture_other";
            pumpReturnJobs();
            check(_root.__bookReturnOpens == 0, "changed slot cancels a queued return opener");
            org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady", _root.gameworld, "", identity);
            _root.gameworld.removeMovieClip();
            _root.gameworld = _root.createEmptyMovieClip("bookFixtureWorld", 9230);
            pumpReturnJobs();
            check(_root.__bookReturnOpens == 0, "same-path replacement world cannot inherit a queued return opener");
        } finally {
            org.flashNight.arki.ui.SceneTransitionService.clear();
            transitionClass.sendOverride = oldSend;
            for (k = 0; k < keys.length; k++) _root[keys[k]] = saved[keys[k]];
        }
    }
    /** 覆盖真正的换槽提交、旧世界清场、到达与自动重开；返回原档也必须等揭幕。 */
    private static function testContextArrivalWaitsForCurtain():Void {
        var keys:Array = ["帧计时器", "当前为战斗地图", "_webPanelPauseLease", "加载背景列表",
            "__bookReturnJobs", "__bookReturnOpens", "__bookCurtain", "gameCommands", "__bookAdmissionCalls"];
        var saved:Object = {};
        for (var k:Number = 0; k < keys.length; k++) saved[keys[k]] = _root[keys[k]];
        var transitionClass:Object = org.flashNight.arki.ui.SceneTransitionService;
        var oldSend:Function = transitionClass.sendOverride;
        _root.帧计时器 = {添加单次任务:function(fn:Function, delay:Number):Void { _root.__bookReturnJobs.push(fn); }};
        transitionClass.sendOverride = function(packet:Object):Boolean { _root.__bookCurtain = packet; return true; };
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        BookshelfPanelService.install();
        var stageClass:Object = org.flashNight.arki.scene.StageRunSession;
        var oldAdmission:Function = stageClass.canStartStage;
        try {
            var kinds:Array = ["switch", "return"];
            for (var i:Number = 0; i < kinds.length; i++) {
                setup();
                _root.当前为战斗地图 = false; _root._webPanelPauseLease = undefined;
                _root.加载背景列表 = null; _root.__bookReturnJobs = []; _root.__bookReturnOpens = 0;
                var snapshot:Object = {ext:{marker:"B"}};
                if (kinds[i] == "return") {
                    var run:Object = {slot:"book_fixture_a", originSlot:"book_fixture_b", seed:17,
                        bookId:"repair-campus", started:true, outcome:"failure", elapsedMs:60000};
                    _root._saveExt.bookRun = run;
                    snapshot.ext.bookshelf = {active:PersistedSnapshot.clone(run)};
                }
                var token:String = open();
                var result:Object = BookshelfPanelService.execute("commit", {v:1, token:token,
                    kind:kinds[i], target:"book_fixture_b", snapshot:snapshot});
                check(result.phase == "switching", kinds[i] + ": real context command accepts one transition");
                _root.server.sendSocketMessage = function(message:String):Boolean {
                    _root.__bookWire = message; _root.__bookReturnOpens++; return true;
                };
                var fade:Object = {_currentframe:5, play:function():Void {}, stop:function():Void {}};
                _root.淡出动画 = fade;
                org.flashNight.arki.ui.SceneTransitionService.begin(fade);
                var packet:Object = _root.__bookCurtain;
                org.flashNight.arki.ui.SceneTransitionService.presented({requestId:packet.requestId,
                    revision:packet.revision, kind:"covered"});
                _root.gameworld.removeMovieClip(); delete _root.gameworld;
                check(BookshelfPanelService.applyAtSceneBoundary() && _root.savePath == "book_fixture_b"
                    && fake.replacements == 1, kinds[i] + ": covered boundary replaces context once");
                BookshelfPanelService.execute("query", {v:1, token:token});
                fade._currentframe = 17; fade.__returnFadeActive = false;
                _root.gameworld = _root.createEmptyMovieClip("bookFixtureWorld", 9230);
                var identity:Object = StageReturnFlow.worldIdentity(_root.gameworld);
                org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady", _root.gameworld, "", identity);
                org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady", _root.gameworld, "", identity);
                pumpReturnJobs();
                check(_root.__bookReturnOpens == 0, kinds[i] + ": new context cannot pause an active curtain");
                check(BookshelfPanelService.openPanel() === false && _root.__bookReturnOpens == 0,
                    kinds[i] + ": direct opener also rejects the curtain without replacing the accepted session");
                check(BookshelfPanelService.execute("snapshot", {v:1, token:token}).canSwitch == false,
                    kinds[i] + ": arrival does not advertise another switch before presentation finishes");
                fade._currentframe = 30;
                org.flashNight.arki.ui.SceneTransitionService.awaitReveal(fade);
                packet = _root.__bookCurtain;
                org.flashNight.arki.ui.SceneTransitionService.presented({requestId:packet.requestId,
                    revision:packet.revision, kind:"revealed"});
                pumpReturnJobs();
                check(_root.__bookReturnOpens == 0, kinds[i] + ": accepted reveal still waits for successful tail");
                fade._currentframe = 36;
                org.flashNight.arki.ui.SceneTransitionService.clear();
                pumpReturnJobs(); pumpReturnJobs();
                check(_root.__bookReturnOpens == (kinds[i] == "return" ? 0 : 1) && fake.replacements == 1,
                    kinds[i] + ": return retains its existing panel; ordinary switch opens once");
                if (kinds[i] == "return") {
                    result = BookshelfPanelService.execute("query", {v:1, token:token});
                    check(result.phase == "applied" && result.nextToken != token && result.nextToken.indexOf("bookshelf.") == 0,
                        "retained return issues original character capability only after curtain retirement");
                    check(BookshelfPanelService.execute("snapshot", {v:1, token:result.nextToken}).activeSlot == "book_fixture_b",
                        "same panel successor reads the restored character without reopening");
                    check(BookshelfPanelService.execute("query", {v:1, token:token}).nextToken == result.nextToken
                            && fake.replacements == 1, "late return query cannot repeat context replacement");
                }
            }
            setup();
            _root._saveExt.bookRun = {outcome:"active"};
            _root.__bookReturnJobs = []; _root.__bookAdmissionCalls = 0;
            stageClass.canStartStage = function():Boolean { _root.__bookAdmissionCalls++; return false; };
            fade = {_currentframe:5, play:function():Void {}, stop:function():Void {}};
            _root.淡出动画 = fade;
            org.flashNight.arki.ui.SceneTransitionService.begin(fade);
            packet = _root.__bookCurtain;
            org.flashNight.arki.ui.SceneTransitionService.presented({requestId:packet.requestId, revision:packet.revision, kind:"covered"});
            fade._currentframe = 17; fade.__returnFadeActive = false;
            _root.gameworld.removeMovieClip();
            _root.gameworld = _root.createEmptyMovieClip("bookFixtureWorld", 9230);
            identity = StageReturnFlow.worldIdentity(_root.gameworld);
            org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady", _root.gameworld, "", identity);
            org.flashNight.arki.scene.BookRunService.queueStart();
            pumpReturnJobs();
            check(_root.__bookAdmissionCalls == 0, "book entry cannot start a second transition behind the first curtain");
            fade._currentframe = 30;
            org.flashNight.arki.ui.SceneTransitionService.awaitReveal(fade);
            packet = _root.__bookCurtain;
            org.flashNight.arki.ui.SceneTransitionService.presented({requestId:packet.requestId, revision:packet.revision, kind:"revealed"});
            fade._currentframe = 36;
            org.flashNight.arki.ui.SceneTransitionService.clear(); pumpReturnJobs();
            check(_root.__bookAdmissionCalls == 1, "book entry resumes admission after actual successful curtain release");
        } finally {
            stageClass.canStartStage = oldAdmission;
            org.flashNight.arki.ui.SceneTransitionService.clear();
            transitionClass.sendOverride = oldSend;
            for (k = 0; k < keys.length; k++) _root[keys[k]] = saved[keys[k]];
        }
    }
    private static function testDirectStageReturn():Void {
        var stageClass:Object = org.flashNight.arki.scene.StageRunSession;
        var managerClass:Object = org.flashNight.arki.scene.StageManager;
        var oldBook:Function = stageClass.canReturnBookContext, oldNav:Function = stageClass.canNavigateAwayFromStage;
        var oldAuthority:Function = stageClass.getRunAuthority, oldDismiss:Function = stageClass.dismissParallelReport;
        var oldComplete:Function = stageClass.completeReturnAttempt, oldManager:Function = managerClass.getInstance;
        var oldBattle = _root.当前为战斗地图, oldType = _root.关卡类型;
        stageClass.canReturnBookContext = function() { return fixtureSave().bookStashed === true; };
        stageClass.canNavigateAwayFromStage = function() { return false; };
        stageClass.getRunAuthority = function() { return {runId:"book.stage.fixture"}; };
        stageClass.dismissParallelReport = function(id) { fixtureSave().dismissed = id; };
        stageClass.completeReturnAttempt = function() {};
        managerClass.getInstance = function() { return {clear:function() {
            fixtureSave().cleared++; throw new Error("synthetic cleanup projection failure");
        }}; };
        try {
            setup(); fake.cleared = 0;
            _root.当前为战斗地图 = true; _root.关卡类型 = "无限过图";
            _root.savePath = "bookrun_fixture";
            var run:Object = {slot:"bookrun_fixture",originSlot:"book_fixture_a",seed:17,bookId:"repair-campus",outcome:"victory",elapsedMs:1200000};
            _root._saveExt.bookRun = run;
            var token:String = open();
            var p:Object = {v:1,token:token,kind:"return",target:"book_fixture_a",snapshot:{ext:{bookshelf:{active:run}}}};
            check(BookshelfPanelService.execute("commit", p).error == "busy" && fake.cleared == 0,
                "battle return cannot bypass unfinished stage settlement");
            fake.bookStashed = true; fake.fence = false;
            check(BookshelfPanelService.execute("commit", p).phase == "save_pending" && fake.cleared == 0 && _root.__bookFades == 0,
                "unknown temporary save cannot unload the battle or expose a base scene");
            fake.fence = true;
            var result:Object = BookshelfPanelService.execute("query", {v:1,token:token});
            check(result.phase == "switching" && fake.cleared == 1 && _root.当前为战斗地图 === false
                    && _root.savePath == "bookrun_fixture" && _root.gameworld._parent != undefined,
                "accepted single fade retires stage but keeps temporary authority until world destruction");
            check(fake.dismissed == "book.stage.fixture", "temporary report is retired only after accepted return fade");
            _root.gameworld.removeMovieClip(); delete _root.gameworld;
            check(BookshelfPanelService.applyAtSceneBoundary() && _root.savePath == "book_fixture_a"
                    && _root._saveExt.bookRun == null && _root.技能点数 == 145,
                "covered scene boundary restores original character and grants only the SP result");
            BookshelfPanelService.applyAtSceneBoundary();
            BookshelfPanelService.execute("query", {v:1,token:token});
            check(fake.replacements == 1 && _root.技能点数 == 145, "boundary/query repeats do not repeat context replacement or SP");
        } finally {
            stageClass.canReturnBookContext = oldBook; stageClass.canNavigateAwayFromStage = oldNav;
            stageClass.getRunAuthority = oldAuthority; stageClass.dismissParallelReport = oldDismiss;
            stageClass.completeReturnAttempt = oldComplete; managerClass.getInstance = oldManager;
            _root.当前为战斗地图 = oldBattle; _root.关卡类型 = oldType;
        }
    }
    /** 生产书架接纳、实际 admission 与关卡准备；仅存储、环境、manager 为受控 fixture。 */
    private static function testDirectBookEntry():Void {
        var runClass:Object = org.flashNight.arki.scene.BookRunService;
        var stageClass:Object = org.flashNight.arki.scene.StageRunSession;
        var managerClass:Object = org.flashNight.arki.scene.StageManager;
        var weatherClass:Object = org.flashNight.arki.weather.WeatherSystem;
        var oldManager:Function = managerClass.getInstance, oldWeather:Function = weatherClass.getInstance;
        var keys:Array = ["关卡回调函数","限制系统","当前为战斗地图","当前关卡名","当前关卡难度",
            "关卡类型","关卡地图帧值","场景进入位置名","难度等级","帧计时器","__bookReturnJobs"];
        var saved:Object = {};
        for (var k:Number = 0; k < keys.length; k++) saved[keys[k]] = _root[keys[k]];
        _root.关卡回调函数 = {}; _root.限制系统 = {openEntries:function():Void {}};
        _root.当前为战斗地图 = false;
        _root.帧计时器 = {添加单次任务:function(fn:Function):Void { _root.__bookReturnJobs.push(fn); }};
        managerClass.getInstance = function():Object { return fixtureSave().manager; };
        weatherClass.getInstance = function():Object { return {getEnvConfig:function():Object {
            return {getStageEnv:function():Object { return {Xmin:100,Ymin:200}; }};
        }}; };
        try {
            setup(); stageClass.testOnlyReset();
            fake.manager = {initialize:function(stages, unused, reservation, allow, rewards, name):Boolean {
                var f:Object = fixtureSave(); f.initialized++; f.stageToken = reservation;
                f.stageCount = stages.length; f.merchantX = stages[0].Instances.Instance[0].x;
                f.preparedSlot = String(_root.savePath); f.worldGone = _root.gameworld._parent == undefined;
                f.ordinaryAdmission = org.flashNight.arki.scene.StageRunSession.reserveStageStart("other", "other", "简单");
                f.foreignAdmission = org.flashNight.arki.scene.StageRunSession.reserveBookshelfEntry("foreign", name);
                f.currentAdmission = org.flashNight.arki.scene.StageRunSession.isStageStartReservationValid(reservation);
                return true;
            }, abortPreparedStage:function():Void { fixtureSave().aborts++; }};
            fake.initialized = 0; fake.aborts = 0; _root.__bookReturnJobs = [];
            var token:String = open();
            BookshelfPanelService.execute("commit", {v:1,token:token,kind:"play",target:"repair-campus",runSlot:"bookrun_direct"});
            BookshelfPanelService.execute("query", {v:1,token:token});
            check(_root.__bookFrame == "wuxianguotu_1" && _root.__bookFades == 1,
                "play targets battle on the original fade; no dorm frame requested");
            check(!runClass.prepareAtSceneBoundary() && fake.initialized == 0,
                "external prepare cannot adopt an active old world");
            _root.场景转换中 = true; _root.淡出动画.__returnFadeActive = true;
            _root.gameworld.removeMovieClip(); delete _root.gameworld;
            check(BookshelfPanelService.applyAtSceneBoundary("wuxianguotu_1") && fake.replacements == 1,
                "one covered boundary adopts and prepares the run directly");
            check(fake.worldGone && fake.preparedSlot == "bookrun_direct" && fake.currentAdmission,
                "stage preparation follows world disposal and the new slot exact reservation");
            check(fake.stageCount == 7 && fake.merchantX == 280 && _root._saveExt.bookRun.started === true,
                "production run plan and environment are prepared before entering battle");
            check(fake.ordinaryAdmission == "" && fake.foreignAdmission == "",
                "covered entry does not relax ordinary or foreign stage admission");
            check(!BookshelfPanelService.isPreparingBookEntry("bookrun_direct") && !runClass.prepareAtSceneBoundary(),
                "synchronous boundary capability expires after preparation");
            BookshelfPanelService.applyAtSceneBoundary("wuxianguotu_1");
            check(fake.replacements == 1 && fake.initialized == 1 && _root.__bookFades == 1,
                "boundary replay cannot replace, initialize, or fade twice");
            stageClass.cancelStageStart(fake.stageToken);
            _root.当前为战斗地图 = true;
            _root.gameworld = _root.createEmptyMovieClip("bookFixtureWorld",9230);
            org.flashNight.neur.Event.EventBus.getInstance().publish("SceneReady",_root.gameworld,"",StageReturnFlow.worldIdentity(_root.gameworld));
            check(BookshelfPanelService.execute("query",{v:1,token:token}).phase == "applied" && _root.__bookReturnJobs.length == 0,
                "battle arrival acknowledges the switch without queueing a second transition");

            _root.当前为战斗地图 = false;
            var manager:Object = fake.manager;
            setup(); stageClass.testOnlyReset(); fake.manager = manager; fake.initialized = 0; fake.aborts = 0;
            token = open();
            BookshelfPanelService.execute("commit", {v:1,token:token,kind:"play",target:"repair-campus",runSlot:"bookrun_retry"});
            BookshelfPanelService.execute("query", {v:1,token:token});
            fake.flushBeforeTransition = function():Boolean { return String(_root.savePath) != "bookrun_retry" || this.tempSaved === true; };
            _root.场景转换中 = true; _root.淡出动画.__returnFadeActive = true;
            _root.gameworld.removeMovieClip(); delete _root.gameworld;
            check(!BookshelfPanelService.applyAtSceneBoundary("wuxianguotu_1") && fake.aborts == 1
                    && _root._saveExt.bookRun.started === false,
                "unconfirmed temporary save cancels reservation and keeps the loading curtain");
            check(stageClass.getCurrentRunId() == "" && !stageClass.isStageStartReservationValid(fake.stageToken),
                "failed entry leaves no live stage or reservation");
            fake.tempSaved = true;
            check(BookshelfPanelService.applyAtSceneBoundary("wuxianguotu_1") && fake.replacements == 1 && fake.initialized == 2,
                "explicit retry prepares the already adopted slot without replaying the origin transaction");
            stageClass.cancelStageStart(fake.stageToken);

            setup(); stageClass.testOnlyReset(); token = open();
            BookshelfPanelService.execute("commit", {v:1,token:token,kind:"play",target:"repair-campus",runSlot:"bookrun_rejected"});
            BookshelfPanelService.execute("query", {v:1,token:token});
            fake.replacePlayerContext = function(slot, snapshot, run):Boolean {
                this.replacements++; if (run != null) return false;
                _root.savePath = slot; _root._saveExt = PersistedSnapshot.clone(snapshot.ext); return true;
            };
            _root.gameworld.removeMovieClip(); delete _root.gameworld;
            check(BookshelfPanelService.applyAtSceneBoundary("wuxianguotu_1") && _root.savePath == "book_fixture_a"
                    && BookshelfPanelService.takeBoundaryFrame("wuxianguotu_1") == "房间",
                "failed context adoption restores original character and redirects away from battle");
            check(BookshelfPanelService.takeBoundaryFrame("other") == "other",
                "recovery redirect is consumed once and cannot rewrite later scene navigation");
        } finally {
            stageClass.testOnlyReset(); managerClass.getInstance = oldManager; weatherClass.getInstance = oldWeather;
            for (k = 0; k < keys.length; k++) _root[keys[k]] = saved[keys[k]];
        }
    }
    public static function runAllTests():Void {
        passed = 0; failed = 0;
        var result:Object;
        var saveClass:Object = org.flashNight.neur.Server.SaveManager;
        var stageClass:Object = org.flashNight.arki.scene.StageRunSession;
        var assetClass:Object = org.flashNight.arki.item.PlayerAssetTransaction;
        var rewardClass:Object = org.flashNight.arki.item.RewardStashService;
        var oldGet:Function = saveClass.getInstance, oldNav:Function = stageClass.canNavigateAwayFromStage;
        var oldCurrent:Function = assetClass.current, oldBegin:Function = rewardClass.begin, oldEnd:Function = rewardClass.end;
        var oldEffect:Function = assetClass.recordEffect;
        assetClass.recordEffect = function(direction, kind, name, count, context):Void {
            _root.__bookEffects.push({direction:direction, kind:kind, name:name, count:count, context:context});
        };
        saveClass.getInstance = function() { return org.flashNight.arki.ui.BookshelfPanelServiceTest.fixtureSave(); };
        stageClass.canNavigateAwayFromStage = function() { return true; };
        assetClass.current = function() { return null; };
        rewardClass.begin = function(id, context, callback, domain) {
            _root.__bookEntry = {id:id,callback:callback,domain:domain}; return true;
        };
        rewardClass.end = function() { org.flashNight.arki.ui.BookshelfPanelServiceTest.fixtureSave().pending = true; return {}; };
        try {
            setup(); var token:String = open();
            check(BookshelfPanelService.execute("snapshot", {v:1,token:token}).unlocked, "metro completion unlocks playable book");
            check(BookshelfPanelService.execute("commit", {v:1,token:token,kind:"play",target:"repair-campus",runSlot:"bookrun_fixture",sp:900}).error == "invalid_payload", "extra reward write rejected");
            check(BookshelfPanelService.execute("snapshot", {v:1,token:"bookshelf.absent"}).error == "stale_token", "invented token rejected");
            _root.tasks_finished = {};
            check(BookshelfPanelService.execute("commit", {v:1,token:token,kind:"play",target:"repair-campus",runSlot:"bookrun_fixture"}).error == "locked", "early story gate");
            setup(); token = open();
            var oldWorld:MovieClip = _root.gameworld;
            _root.gameworld.removeMovieClip();
            _root.gameworld = _root.createEmptyMovieClip("bookFixtureWorld", 9230);
            result = BookshelfPanelService.execute("commit", {v:1,token:token,kind:"switch",target:"b",snapshot:{ext:{}}});
            check(result.phase == "expired" && result.kind == "switch" && result.target == "b"
                && result.error == "not_executed" && _root.__bookFades == 0 && fake.replacements == 0,
                "same-path real MovieClip cannot inherit session and gets exact negative receipt");
            setup(); token = open();
            result = BookshelfPanelService.execute("query", {v:1,token:token,reconcileKind:"switch",reconcileTarget:"b"});
            check(result.phase == "expired" && result.kind == "switch", "negative reconciliation retires unaccepted operation");
            check(BookshelfPanelService.execute("commit", {v:1,token:token,kind:"switch",target:"b",snapshot:{ext:{}}}).phase == "expired" && _root.__bookFades == 0, "late commit cannot execute after negative receipt");
            setup(); token = open(); _root.savePath = "other";
            check(BookshelfPanelService.execute("query", {v:1,token:token}).phase == "expired", "query expires old save identity");
            setup(); token = open();
            var snapshot:Object = {ext:{marker:"B"}};
            var request:Object = {v:1,token:token,kind:"switch",target:"book_fixture_b",snapshot:snapshot};
            result = BookshelfPanelService.execute("commit", request);
            check(result.phase == "switching" && _root.savePath == "book_fixture_a", "acceptance waits for covered scene boundary");
            snapshot.ext.marker = "changed";
            BookshelfPanelService.execute("commit", request);
            check(_root.__bookFades == 1, "duplicate commit does not start another transition");
            check(BookshelfPanelService.execute("commit", {v:1,token:token,kind:"switch",target:"c",snapshot:{ext:{}}}).error == "token_conflict", "changed target cannot reuse token");
            _root.gameworld.removeMovieClip(); delete _root.gameworld;
            check(BookshelfPanelService.applyAtSceneBoundary(), "covered boundary adopts canonical context");
            check(_root.savePath == "book_fixture_b" && _root._saveExt.marker == "B", "detached canonical target cannot alias incoming envelope");
            BookshelfPanelService.applyAtSceneBoundary();
            check(fake.replacements == 1, "boundary replay does not reload context");
            setup(); token = open(); fake.fence = false;
            result = BookshelfPanelService.execute("commit", {v:1,token:token,kind:"switch",target:"b",snapshot:{ext:{}}});
            check(result.phase == "save_pending" && _root.__bookFades == 0 && fake.replacements == 0, "unknown source save cannot change scene or slot");
            fake.fence = true;
            check(BookshelfPanelService.execute("query", {v:1,token:token}).phase == "switching", "exact query continues after source fence");
            setup(); token = open();
            result = BookshelfPanelService.execute("commit", {v:1,token:token,kind:"play",target:"repair-campus",runSlot:"bookrun_fixture"});
            check(result.phase == "save_pending" && _root.__bookFades == 0, "run entry waits for durable origin marker");
            check(_root._saveExt.bookshelf.active.originSlot == "book_fixture_a", "entry credentials bind original slot");
            result = BookshelfPanelService.execute("query", {v:1,token:token});
            check(result.phase == "switching" && _root.__bookFades == 1, "confirmed entry begins one fade");
            setup(); token = open();
            var active:Object = {slot:"bookrun_fixture",originSlot:"book_fixture_a",seed:17,bookId:"repair-campus",outcome:"active"};
            _root._saveExt.bookshelf = {active:active};
            var finalRun:Object = PersistedSnapshot.clone(active); finalRun.outcome = "victory"; finalRun.elapsedMs = 20 * 60000;
            result = BookshelfPanelService.execute("commit", {v:1,token:token,kind:"settle",target:"bookrun_fixture",snapshot:{ext:{bookRun:finalRun}}});
            check(result.phase == "save_pending" && _root.技能点数 == 145, "reward and receipt share pending candidate");
            check(result.records.history.length == 0 && result.lastReward == 0 && result.reward == 0,
                "unconfirmed candidate does not advertise SP or history as committed");
            check(_root.__bookEffects.length == 1 && _root.__bookEffects[0].kind == "skillpoint"
                    && _root.__bookEffects[0].count == 45 && _root.__bookEffects[0].context.source == "level_reward",
                "SP notification joins the durable reward asset transaction");
            BookshelfPanelService.execute("commit", {v:1,token:token,kind:"settle",target:"bookrun_fixture",snapshot:{ext:{bookRun:finalRun}}});
            check(_root.技能点数 == 145, "duplicate pending result does not grant twice");
            check(_root.__bookEffects.length == 1, "duplicate pending commit does not queue another SP notification");
            result = BookshelfPanelService.execute("query", {v:1,token:token});
            check(result.phase == "applied" && _root._saveExt.bookshelf.active == null, "confirmed reward consumes origin marker");
            check(result.records.history.length == 1 && result.records.history[0].runId == finalRun.slot
                    && result.records.history[0].reason == "first_clear" && result.records.history[0].sp == 45
                    && result.records.bestMs == finalRun.elapsedMs && result.records.clears == 1,
                "confirmed result preserves last run, record and actually paid SP");
            var freshToken:String = result.nextToken;
            check(freshToken != token && freshToken.indexOf("bookshelf.") == 0, "completed reconciliation issues a separate editing capability");
            check(BookshelfPanelService.execute("query", {v:1,token:token}).nextToken == freshToken,
                "lost terminal response recovers the same successor rather than minting repeatedly");
            check(BookshelfPanelService.execute("commit", {v:1,token:token,kind:"play",target:"repair-campus",runSlot:"bookrun_new"}).error == "token_conflict",
                "completed operation cannot be repurposed into a new run");
            check(BookshelfPanelService.execute("snapshot", {v:1,token:freshToken}).phase == "editing",
                "same open panel can immediately read the new editing session");
            token = freshToken;
            check(BookshelfPanelService.execute("commit", {v:1,token:token,kind:"settle",target:"bookrun_fixture",snapshot:{ext:{bookRun:finalRun}}}).error == "invalid_target", "new session cannot replay consumed run");
            setup(); token = open(); _root._saveExt.bookshelf = {active:active};
            finalRun.seed = 18;
            check(BookshelfPanelService.execute("commit", {v:1,token:token,kind:"settle",target:"bookrun_fixture",snapshot:{ext:{bookRun:finalRun}}}).error == "invalid_target", "foreign run credential rejected");
            setup(); token = open(); _root._saveExt.bookshelf = {active:active};
            result = BookshelfPanelService.execute("commit", {v:1,token:token,kind:"settle",target:"bookrun_fixture",missingRun:true});
            check(result.phase == "save_pending" && _root.技能点数 == 100, "verified missing run retires without reward");
            check(_root.__bookEffects.length == 0, "abandoned run does not publish a positive reward");
            setup(); token = open();
            var oldHistory:Array = [];
            for (var h:Number = 0; h < 20; h++) oldHistory.push({runId:"old." + h, sp:5});
            _root._saveExt.bookshelf = {active:active, history:oldHistory, firstClear:true, bestMs:600000, clears:20};
            finalRun.seed = active.seed; finalRun.outcome = "failure";
            BookshelfPanelService.execute("commit", {v:1,token:token,kind:"settle",target:"bookrun_fixture",snapshot:{ext:{bookRun:finalRun}}});
            result = BookshelfPanelService.execute("query", {v:1,token:token});
            check(result.records.history.length == 20 && result.records.history[0].outcome == "failure"
                    && result.records.history[19].runId == "old.18", "history keeps newest twenty results including failures");
            check(result.records.bestMs == 600000 && result.records.clears == 20 && result.lastReward == 0,
                "failed last run preserves all-time best and clears but never reuses previous SP");
            testDirectStageReturn();
            testReturnUiWaitsForCurtain();
            testContextArrivalWaitsForCurtain();
            testDirectBookEntry();
        } finally {
            saveClass.getInstance = oldGet; stageClass.canNavigateAwayFromStage = oldNav;
            assetClass.current = oldCurrent; assetClass.recordEffect = oldEffect; rewardClass.begin = oldBegin; rewardClass.end = oldEnd;
            BookshelfPanelService._resetForTests();
            if (_root.gameworld != undefined) _root.gameworld.removeMovieClip();
        }
        trace("BookshelfPanelServiceTest Tests Passed: " + passed);
        trace("BookshelfPanelServiceTest Tests Failed: " + failed);
    }
    public static function fixtureSave():Object { return fake; }
}
