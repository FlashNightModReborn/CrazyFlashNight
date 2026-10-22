import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.BookRunRules;
import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.arki.scene.BookComicService;
import org.flashNight.arki.scene.BookRunClock;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.neur.Event.EventBus;

/** 临时角色仍使用标准关卡、掉落、换装、NPC 商店和技能服务。 */
class org.flashNight.arki.scene.BookRunService {
    private static var _installed:Boolean = false;
    private static var _bossPlan:Object;
    private static var _cf6BossPlans:Object;
    private static var _cf6PlanOwner:Object;
    private static var _startSlot:String = "";
    private static var _ending:Object;
    private static var _debug:Object;
    private static var _returnUi:Object;
    private static var _chapter:Object;
    private static var _chapterWatch:MovieClip;
    private static var _startError:String = "";
    public static function install():Void {
        if (_installed) return;
        _installed = true;
        BookComicService.install();
        BookRunClock.install();
        org.flashNight.arki.scene.Cf6MapMechanism.install();
        org.flashNight.arki.scene.LeeTrialTelemetry.install();
        org.flashNight.arki.scene.LeeAssaultService.install();
        EventBus.getInstance().subscribe("SceneReady", onSceneReady, null);
        EventBus.getInstance().subscribe("SceneTransitionReleased", onTransitionReleased, null);
        // 仅 AS2 开发控制台可调用；调试局明确禁止奖励回流。
        _root.书中调试 = function(seed:Number, startMap:Number):Boolean {
            return org.flashNight.arki.scene.BookRunService.configureDebug(seed, startMap);
        };
    }
    public static function playChapter(index:Number):Void {
        var run:Object = _root._saveExt.bookRun;
        var config:Object = BookDefinition.get();
        if (run.bookId === "lee-trial") return;
        if (!isBookStageContext() || config == null || run.outcome != "active" || isNaN(index) || Math.floor(index) != index
                || index < 0 || index >= config.maps.length) return;
        var owner:Object = org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld);
        if (_chapter != null && _chapter.owner === owner && _chapter.index === index) return;
        _chapter = {index:index, owner:owner, slot:String(_root.savePath), run:run,
            runIdentity:run.bookId === "cf6-sting" ? org.flashNight.gesh.object.PersistedSnapshot.clone(run) : null};
        if (_chapterWatch == null || _chapterWatch._name == undefined)
            _chapterWatch = _root.createEmptyMovieClip("__bookChapterHandoff", _root.getNextHighestDepth());
        _chapterWatch.onEnterFrame = function():Void { org.flashNight.arki.scene.BookRunService.presentChapter(); };
        presentChapter();
    }
    private static function onTransitionReleased(world:Object, token:String, identity:Object):Void {
        if (world !== _root.gameworld || identity == null
                || identity !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(world)) return;
        var run:Object = _root._saveExt.bookRun;
        if (run.bookId === "lee-trial" && run.outcome === "active" && isBookStageContext()) {
            BookRunClock.ensureStarted(run);
            org.flashNight.arki.scene.LeeTrialTelemetry.beginRoom(world, identity);
            org.flashNight.arki.scene.LeeAssaultService.beginRoom(world, identity);
        }
        presentChapter();
    }
    /** 先等加载幕真实退场，再取得漫画/对白暂停；否则暂停会把旧遮幕永久留在下层。 */
    public static function presentChapter():Void {
        var chapter:Object = _chapter;
        if (chapter == null || chapter.started === true || chapter.storyActive === true) return;
        var currentRun:Object=_root._saveExt.bookRun;
        var sameRun:Boolean=chapter.runIdentity != null ? BookRunRules.sameCf6Run(chapter.runIdentity,currentRun) : chapter.run === currentRun;
        if (chapter.slot !== String(_root.savePath) || !sameRun
                || currentRun.outcome != "active"
                || chapter.owner !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)) {
            _chapter = null; delete _chapterWatch.onEnterFrame; return;
        }
        if (org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()
                || _root.淡出动画.__returnFadeActive === true || _root.场景转换中 === true) return;
        // 首次可演出/可操作时才开表；后续章节不会重置已有计时。
        BookRunClock.ensureStarted(currentRun);
        var index:Number = chapter.index;
        var config:Object = BookDefinition.get();
        if (currentRun.bookId === "cf6-sting") {
            var cf6Follow:Function = cf6ChapterContinuation(chapter);
            if (org.flashNight.arki.scene.Cf6StoryService.hasChapterStory(index)) {
                chapter.storyActive = true;
                if (org.flashNight.arki.scene.Cf6StoryService.beginChapter(index, cf6Follow,
                        cf6ChapterInterruption(chapter))) return;
                if (_chapter === chapter && chapter.started !== true) chapter.storyActive = false;
                return;
            }
            cf6Follow("continue", "route");
            return;
        }
        _chapter = null; delete _chapterWatch.onEnterFrame;
        if (index == config.bossEncounter.mapIndex) {
            org.flashNight.arki.scene.BookBossEncounter.start(_root.gameworld,
                _bossPlan);
        }
        var follow:Function = chapterContinuation(index, chapter.owner, chapter.slot);
        var pageId:String = index == 0 ? "prologue" : (index == config.bossEncounter.mapIndex ? "boss" : "");
        if (pageId == "" || !BookComicService.begin(pageId, follow)) follow();
    }
    private static function cf6ChapterContinuation(chapter:Object):Function {
        return function(reason:String, phase:String):Void {
            if ((reason != "continue" && reason != "skip") || _chapter !== chapter || chapter.started === true) return;
            var run:Object = _root._saveExt.bookRun;
            if (chapter.slot !== String(_root.savePath)
                    || !BookRunRules.sameCf6Run(chapter.runIdentity, run) || run.outcome != "active"
                    || chapter.owner !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)) return;
            var config:Object = BookDefinition.get();
            if (config == null || chapter.index < 0 || chapter.index >= config.maps.length) return;
            chapter.started = true; chapter.storyActive = false; delete _chapterWatch.onEnterFrame;
            org.flashNight.arki.scene.Cf6MapMechanism.beginRoom(_root.gameworld, chapter.owner,
                config.maps[chapter.index].id, config.maps[chapter.index].mechanism);
            org.flashNight.arki.scene.Cf6BossEncounter.start(_root.gameworld, chapter.owner,
                org.flashNight.arki.scene.BookRunService.cf6BossPlan(run, chapter.index));
            org.flashNight.arki.scene.BookRunService.showChapterDialogue(chapter.index, chapter.owner, chapter.slot);
        };
    }
    private static function cf6ChapterInterruption(chapter:Object):Function {
        return function(reason:String, phase:String):Void {
            if (_chapter !== chapter || chapter.started === true) return;
            chapter.storyActive = false;
            if (_chapterWatch == null || _chapterWatch._name == undefined)
                _chapterWatch = _root.createEmptyMovieClip("__bookChapterHandoff", _root.getNextHighestDepth());
            _chapterWatch.onEnterFrame = function():Void { org.flashNight.arki.scene.BookRunService.presentChapter(); };
        };
    }
    private static function cf6BossPlan(run:Object,index:Number):Object {
        return run.slot === String(_root.savePath) && BookRunRules.sameCf6Run(_cf6PlanOwner,run)
            ? _cf6BossPlans[String(index)] : null;
    }
    private static function chapterContinuation(index:Number, owner:Object, slot:String):Function {
        return function():Void {
            org.flashNight.arki.scene.BookRunService.showChapterDialogue(index, owner, slot);
        };
    }
    private static function showChapterDialogue(index:Number, owner:Object, slot:String):Void {
        if (slot !== String(_root.savePath) || owner == undefined
                || owner !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)
                || _root._saveExt.bookRun.outcome != "active") return;
        var lines:Array = BookDefinition.get().maps[index].dialogue;
        if (lines.length == 0) return;
        var rows:Array = [];
        for (var i:Number = 0; i < lines.length; i++) {
            rows.push({name:lines[i].speaker, title:"", text:lines[i].text,
                char:lines[i].speaker == "Andy" ? "$PC_CHAR" : "", target:null, imageurl:""});
        }
        org.flashNight.arki.dialogue.NativeDialogueService.beginStage(rows, null);
    }
    public static function configureDebug(seed:Number, startMap:Number):Boolean {
        if (_root._saveExt.bookRun != null || isNaN(seed) || seed < 1 || seed >= 2147483647
            || Math.floor(seed) != seed || isNaN(startMap) || startMap < 0 || startMap >= BookDefinition.get().maps.length || Math.floor(startMap) != startMap) return false;
        _debug = {seed:seed, startMap:startMap}; return true;
    }
    public static function queueStart():Void {
        var run:Object = _root._saveExt.bookRun;
        if (run == null || run.outcome != "active") return;
        _startSlot = String(_root.savePath);
        _root.帧计时器.添加单次任务(tryStart, 1);
    }
    private static function tryStart():Void {
        if (_startSlot == "" || _startSlot !== String(_root.savePath)) return;
        if (org.flashNight.arki.ui.SceneTransitionService.isPresentationPending() || !StageRunSession.canStartStage()) { _root.帧计时器.添加单次任务(tryStart, 1); return; }
        var token:String = prepareStage(false);
        if (token == "") { startFailed(_startError); return; }
        if (_root.淡出动画.淡出跳转帧("wuxianguotu_1") !== true) {
            StageManager.getInstance().abortPreparedStage(token); StageRunSession.cancelStageStart(token);
            startFailed(_root._saveExt.bookRun.bookId === "lee-trial" ? "过场尚未就绪，请返回原角色后重试。" : "过场尚未就绪，请返回书架。");
        }
        _startSlot = "";
    }
    public static function prepareAtSceneBoundary():Boolean {
        if (!org.flashNight.arki.ui.BookshelfPanelService.isPreparingBookEntry(String(_root.savePath))) return false;
        return prepareStage(true) != "";
    }
    private static function prepareStage(coveredEntry:Boolean):String {
        var run:Object = _root._saveExt.bookRun;
        var trial:Boolean = run.bookId === "lee-trial";
        _startError = trial ? "挑战关卡未能准备，请返回原角色。" : "书中关卡未能准备，请返回书架。";
        if (run == null || run.outcome != "active" || run.slot !== String(_root.savePath)
                || (!trial && (!BookDefinition.supports(run.bookId) || !BookDefinition.ready(run.bookId)))
                || (run.bookId === "cf6-sting" && run.routeId !== "historical")) return "";
        var startMap:Number = 0;
        var planSeed:Number = run.seed;
        if (_debug != null) { planSeed = _debug.seed; run.planSeed = planSeed; startMap = _debug.startMap; run.debug = true; _debug = null; }
        // 原档的进入凭据中的 seed 保持不变；调试随机种子单独存放。
        var stages:Array = trial ? org.flashNight.arki.scene.LeeTrialDefinition.stages() : BookRunRules.stages(planSeed, startMap, run.bookId);
        if (stages.length == 0) return "";
        _bossPlan = stages[stages.length - 1].BasicInformation.BookBoss;
        for (var i:Number = 0; i < stages.length; i++) {
            var env:Object = WeatherSystem.getInstance().getEnvConfig().getStageEnv(String(String(stages[i].BasicInformation.Background).split("/").pop()));
            // 环境名称解析与 StageManager 一致；运行前检查，避免默默生成原点商人。
            if (env == null) { _startError = trial ? "挑战地图环境未就绪，请返回原角色。" : "书中地图环境未就绪，请返回书架。"; return ""; }
            if (run.bookId === "repair-campus") {
                stages[i].Instances.Instance[0].x = Number(env.Xmin) + 180;
                stages[i].Instances.Instance[0].y = Number(env.Ymin) + 75;
            }
        }
        _root.关卡回调函数.书中章节 = function(index:Number):Void {
            org.flashNight.arki.scene.BookRunService.playChapter(index);
        };
        var name:String = stageName(run);
        var token:String = coveredEntry ? StageRunSession.reserveBookshelfEntry(String(_root.savePath), name)
            : StageRunSession.reserveStageStart("bookshelf", name, "简单");
        if (token == "") return "";
        var manager:StageManager = StageManager.getInstance();
        if (!manager.initialize(stages, null, token, false, [], name, [])) {
            StageRunSession.cancelStageStart(token); return "";
        }
        // Keep the already selected reinforcement plan, bound to this exact temporary run.
        _cf6BossPlans={}; _cf6PlanOwner=null;
        if (run.bookId === "cf6-sting") for (var cp:Number=0;cp<stages.length;cp++)
            _cf6BossPlans[String(startMap+cp)]=stages[cp].BasicInformation.Cf6Boss;
        _root.当前关卡名 = name; _root.当前关卡难度 = "简单"; _root.难度等级 = 1;
        _root.关卡类型 = "无限过图"; _root.关卡地图帧值 = "房间";
        _root.场景进入位置名 = "出生地";
        _root.限制系统.openEntries(["DisableCompanion"]);
        if (trial && !org.flashNight.arki.scene.LeeAssaultService.prepare(run)) {
            manager.abortPreparedStage(token); StageRunSession.cancelStageStart(token);
            _startError = "本章复活币未能准备，请返回原角色。"; return "";
        }
        run.startedAt = new Date().getTime();
        if (run.bookId === "cf6-sting") _cf6PlanOwner=org.flashNight.gesh.object.PersistedSnapshot.clone(run);
        run.started = true;
        run.playTimeMs = 0; run.clockVersion = 1;
        if (!SaveManager.getInstance().flushBeforeTransition("bookshelf.switch")) {
            manager.abortPreparedStage(token); StageRunSession.cancelStageStart(token);
            run.started = false;
            _startError = trial ? "挑战角色尚未保存，请返回原角色核对。" : "书中角色尚未保存，请返回书架核对。"; return "";
        }
        return token;
    }
    private static function startFailed(message:String):Void {
        _startSlot = "";
        _root.发布消息(message);
        abandonIfActive();
        queueReturnUi();
    }
    public static function finish(outcome:String):Void {
        var run:Object = _root._saveExt.bookRun;
        if (run == null || run.outcome != "active" || _ending != null
            || run.slot !== String(_root.savePath) || (outcome != "victory" && outcome != "failure" && outcome != "defeat" && outcome != "retreat")
            || _root.当前关卡名 !== stageName(run)) return;
        org.flashNight.arki.scene.LeeTrialTelemetry.finish(outcome);
        _ending = {slot:String(_root.savePath), outcome:outcome,
            elapsedMs:BookRunClock.elapsed(run), run:run,
            owner:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld),
            cf6Story:run.bookId === "cf6-sting" && outcome == "victory",
            runIdentity:run.bookId === "cf6-sting" ? org.flashNight.gesh.object.PersistedSnapshot.clone(run) : null};
        if (_ending.cf6Story) presentCf6Ending(); else persistOutcome();
    }
    private static function presentCf6Ending():Void {
        var ending:Object = _ending;
        if (ending == null || !ending.cf6Story || ending.storyCompleted === true
                || ending.storyActive === true || ending.storyRetry === true) return;
        var run:Object = _root._saveExt.bookRun;
        if (ending.slot !== String(_root.savePath) || !BookRunRules.sameCf6Run(ending.runIdentity, run)
                || run.outcome != "active" || ending.owner !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)) {
            _ending = null; return;
        }
        ending.storyActive = true;
        if (org.flashNight.arki.scene.Cf6StoryService.beginFinal(cf6EndingContinuation(ending),
                cf6EndingInterruption(ending))) return;
        if (_ending !== ending || ending.storyCompleted === true) return;
        ending.storyActive = false;
        if (ending.storyRetry !== true) {
            ending.storyRetry = true;
            _root.帧计时器.添加单次任务(cf6EndingRetryCallback(ending), 1);
        }
    }
    private static function cf6EndingRetryCallback(ending:Object):Function {
        return function():Void {
            if (_ending !== ending) return;
            ending.storyRetry = false;
            org.flashNight.arki.scene.BookRunService.presentCf6Ending();
        };
    }
    private static function cf6EndingContinuation(ending:Object):Function {
        return function(reason:String, phase:String):Void {
            if ((reason != "continue" && reason != "skip") || _ending !== ending || ending.storyCompleted === true) return;
            var run:Object = _root._saveExt.bookRun;
            if (ending.slot !== String(_root.savePath) || !BookRunRules.sameCf6Run(ending.runIdentity, run)
                    || run.outcome != "active" || ending.owner !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)) return;
            ending.storyActive = false; ending.storyCompleted = true;
            org.flashNight.arki.scene.BookRunService.persistOutcome();
        };
    }
    private static function cf6EndingInterruption(ending:Object):Function {
        return function(reason:String, phase:String):Void {
            if (_ending !== ending || ending.storyCompleted === true) return;
            ending.storyActive = false;
            if (ending.storyRetry === true) return;
            ending.storyRetry = true;
            _root.帧计时器.添加单次任务(cf6EndingRetryCallback(ending), 1);
        };
    }
    private static function persistOutcome():Void {
        var ending:Object = _ending;
        if (ending == null || (ending.cf6Story === true && ending.storyCompleted !== true)) return;
        var run:Object = _root._saveExt.bookRun;
        if (ending.cf6Story === true && (ending.slot !== String(_root.savePath)
                || run == null || !BookRunRules.sameCf6Run(ending.runIdentity, run) || run.outcome != "active"
                || ending.owner !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld))) {
            _ending = null; return;
        }
        if (ending.slot !== String(_root.savePath)) { _ending = null; return; }
        if (SaveManager.getInstance().hasRewardCommitPending()) {
            _root.帧计时器.添加单次任务(persistOutcome, 1); return;
        }
        // 终局结果属于临时角色。复用正规返回基地及书架换槽的全量保存屏障，
        // 不在战斗结算前插入另一份独立奖励候选，避免两个候选互相阻塞。
        var sameRun:Boolean=ending.runIdentity != null ? BookRunRules.sameCf6Run(ending.runIdentity,run) : run === ending.run;
        if (run == null || !sameRun || run.slot !== ending.slot || run.outcome !== "active") { _ending = null; return; }
        run.outcome = ending.outcome;
        run.elapsedMs = ending.elapsedMs;
        _root.存档系统.markDirty();
        _ending = null;
    }
    public static function hasUnsettledOutcome():Boolean {
        return _ending != null && _ending.slot === String(_root.savePath);
    }
    public static function reconcileOutcome():Void {
        if (!hasUnsettledOutcome()) return;
        if (_ending.cf6Story === true && _ending.storyCompleted !== true) presentCf6Ending();
        else persistOutcome();
    }
    public static function abandonIfActive():Void {
        var run:Object = _root._saveExt.bookRun;
        if (run != null && run.outcome == "active") {
            org.flashNight.arki.scene.LeeTrialTelemetry.finish("abandoned");
            run.elapsedMs = BookRunClock.elapsed(run);
            run.outcome = "abandoned";
        }
    }
    private static function onSceneReady(world:Object, token:String, identity:Object):Void {
        if (_root._saveExt.bookRun == null || _root.当前为战斗地图 === true
            || world !== _root.gameworld || identity == null || identity !== world.__stageReturnWorldIdentity) return;
        var run:Object = _root._saveExt.bookRun;
        if (run.started !== true && run.outcome == "active") return;
        if (run.outcome == "active") abandonIfActive();
        queueReturnUi();
    }
    public static function requestReturn():Boolean {
        if (!StageRunSession.canReturnBookContext()) return false;
        queueReturnUi();
        return true;
    }
    private static function queueReturnUi():Void {
        _returnUi = {slot:String(_root.savePath), owner:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)};
        _root.帧计时器.添加单次任务(showReturnUi, 1);
    }
    private static function showReturnUi():Void {
        var r:Object = _returnUi;
        if (r == null) return;
        if (r.slot !== String(_root.savePath) || r.owner !== org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)) {
            _returnUi = null; return;
        }
        // 原生关卡报告优先；frame 17 放行场景初始化，不代表过场已结束。
        // 书架会暂停游戏，必须等过场服务完成揭幕和尾帧释放后再打开。
        if ((!StageRunSession.canReturnBookContext() && StageRunSession.hasUnpresentedSettlementReport()) || _root._webPanelPauseLease != undefined
                || org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()
                || _root.淡出动画.__returnFadeActive === true || _root.场景转换中 === true) {
            _root.帧计时器.添加单次任务(showReturnUi, 1); return;
        }
        _returnUi = null;
        StageRunSession.completeReturnAttempt();
        if (!org.flashNight.arki.ui.BookshelfPanelService.openPanel()) {
            StageRunSession.failReturnAttempt("return_base_failed");
            _root.发布消息(_root._saveExt.bookRun.bookId === "lee-trial"
                ? "返回结算界面未能打开，请再次选择结束挑战。" : "返回书架未能打开，请再次选择结束旅程。");
        }
    }
    /** 只有当前槽位的书中关卡走房间；普通角色的医务室及任务返回规则保持原样。 */
    public static function isBookStageContext():Boolean {
        var run:Object = _root._saveExt.bookRun;
        return run != null && run.slot === String(_root.savePath)
            && (BookDefinition.supports(run.bookId) || run.bookId === "lee-trial")
            && (run.bookId !== "cf6-sting" || run.routeId === "historical")
            && _root.当前关卡名 === stageName(run);
    }
    private static function stageName(run:Object):String {
        return run.bookId === "lee-trial" ? String(org.flashNight.arki.scene.LeeTrialDefinition.get().stageName)
            : run.bookId === "cf6-sting" ? "书中历险-毒刺行动" : String(BookDefinition.get("repair-campus").stageName);
    }
    public static function playerLevelCapReached():Boolean {
        var run:Object=_root._saveExt.bookRun;
        return run.bookId === "cf6-sting" && run.routeId === "historical"
            && run.slot === String(_root.savePath) && !isNaN(Number(_root.等级)) && Number(_root.等级) >= 60;
    }
    public static function returnFrame(fallback) {
        return isBookStageContext() ? "房间" : fallback;
    }
}
