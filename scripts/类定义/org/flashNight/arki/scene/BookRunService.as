import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.BookRunRules;
import org.flashNight.arki.scene.BookDefinition;
import org.flashNight.arki.weather.WeatherSystem;
import org.flashNight.neur.Server.SaveManager;
import org.flashNight.neur.Event.EventBus;

/** 临时角色仍使用标准关卡、掉落、换装、NPC 商店和技能服务。 */
class org.flashNight.arki.scene.BookRunService {
    private static var _installed:Boolean = false;
    private static var _bossPlan:Object;
    private static var _startSlot:String = "";
    private static var _ending:Object;
    private static var _debug:Object;
    private static var _returnUi:Object;
    public static function install():Void {
        if (_installed) return;
        _installed = true;
        EventBus.getInstance().subscribe("SceneReady", onSceneReady, null);
        // 仅 AS2 开发控制台可调用；调试局明确禁止奖励回流。
        _root.书中调试 = function(seed:Number, startMap:Number):Boolean {
            return org.flashNight.arki.scene.BookRunService.configureDebug(seed, startMap);
        };
    }
    public static function playChapter(index:Number):Void {
        var run:Object = _root._saveExt.bookRun;
        var config:Object = BookDefinition.get();
        if (run == null || run.outcome != "active" || isNaN(index) || Math.floor(index) != index
                || index < 0 || index >= config.maps.length) return;
        if (index == config.bossEncounter.mapIndex) {
            org.flashNight.arki.scene.BookBossEncounter.start(_root.gameworld,
                _bossPlan);
        }
        _root.书中当前章节 = {index:index, total:config.maps.length, title:config.maps[index].title,
            dialogue:config.maps[index].dialogue, slot:String(_root.savePath),
            owner:org.flashNight.arki.scene.StageReturnFlow.worldIdentity(_root.gameworld)};
        // 独立 SWF 不导入游戏类；暂停租约仍由注入层唯一持有。
        _root.书中过场取得暂停 = function():String {
            return org.flashNight.arki.pause.PauseManager.lease(true, "book_chapter");
        };
        _root.书中过场释放暂停 = function(lease:String):Void {
            org.flashNight.arki.pause.PauseManager.releaseLease(lease);
        };
        _root.最上层加载外部动画("flashswf/movies/修理大学章节.swf");
    }
    public static function configureDebug(seed:Number, startMap:Number):Boolean {
        if (_root._saveExt.bookRun != null || isNaN(seed) || seed < 1 || seed >= 2147483647
            || Math.floor(seed) != seed || isNaN(startMap) || startMap < 0 || startMap > 6 || Math.floor(startMap) != startMap) return false;
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
        var run:Object = _root._saveExt.bookRun;
        if (run == null || run.outcome != "active") { _startSlot = ""; return; }
        var startMap:Number = 0;
        var planSeed:Number = run.seed;
        if (_debug != null) { planSeed = _debug.seed; run.planSeed = planSeed; startMap = _debug.startMap; run.debug = true; _debug = null; }
        // 原档的进入凭据中的 seed 保持不变；调试随机种子单独存放。
        var stages:Array = BookRunRules.stages(planSeed, startMap);
        _bossPlan = stages[stages.length - 1].BasicInformation.BookBoss;
        for (var i:Number = 0; i < stages.length; i++) {
            var env:Object = WeatherSystem.getInstance().getEnvConfig().getStageEnv(String(String(stages[i].BasicInformation.Background).split("/").pop()));
            // 环境名称解析与 StageManager 一致；运行前检查，避免默默生成原点商人。
            if (env == null) { startFailed("书中地图环境未就绪，请返回书架。"); return; }
            stages[i].Instances.Instance[0].x = Number(env.Xmin) + 180;
            stages[i].Instances.Instance[0].y = Number(env.Ymin) + 75;
        }
        _root.关卡回调函数.书中章节 = function(index:Number):Void {
            org.flashNight.arki.scene.BookRunService.playChapter(index);
        };
        var name:String = BookDefinition.get().stageName;
        var token:String = StageRunSession.reserveStageStart("bookshelf", name, "简单");
        if (token == "") return;
        var manager:StageManager = StageManager.getInstance();
        if (!manager.initialize(stages, null, token, false, [], name, [])) {
            StageRunSession.cancelStageStart(token); startFailed("书中关卡未能准备，请返回书架。"); return;
        }
        _root.当前关卡名 = name; _root.当前关卡难度 = "简单"; _root.难度等级 = 1;
        _root.关卡类型 = "无限过图"; _root.关卡地图帧值 = "房间";
        _root.场景进入位置名 = "出生地";
        _root.限制系统.openEntries(["DisableCompanion"]);
        run.startedAt = new Date().getTime();
        run.started = true;
        if (!SaveManager.getInstance().flushBeforeTransition("bookshelf.switch")) {
            manager.abortPreparedStage(token); StageRunSession.cancelStageStart(token);
            startFailed("书中角色尚未保存，请返回书架核对。"); return;
        }
        if (_root.淡出动画.淡出跳转帧("wuxianguotu_1") !== true) {
            manager.abortPreparedStage(token); StageRunSession.cancelStageStart(token);
            startFailed("过场尚未就绪，请返回书架。");
        }
        _startSlot = "";
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
            || _root.当前关卡名 !== BookDefinition.get().stageName) return;
        _ending = {slot:String(_root.savePath), outcome:outcome,
            elapsedMs:Math.max(1, new Date().getTime() - Number(run.startedAt)), run:run};
        persistOutcome();
    }
    private static function persistOutcome():Void {
        var ending:Object = _ending;
        if (ending == null) return;
        if (ending.slot !== String(_root.savePath)) { _ending = null; return; }
        if (SaveManager.getInstance().hasRewardCommitPending()) {
            _root.帧计时器.添加单次任务(persistOutcome, 1); return;
        }
        // 终局结果属于临时角色。复用正规返回基地及书架换槽的全量保存屏障，
        // 不在战斗结算前插入另一份独立奖励候选，避免两个候选互相阻塞。
        var run:Object = _root._saveExt.bookRun;
        if (run == null || run.slot !== ending.slot) { _ending = null; return; }
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
        persistOutcome();
    }
    public static function abandonIfActive():Void {
        var run:Object = _root._saveExt.bookRun;
        if (run != null && run.outcome == "active") {
            run.outcome = "abandoned";
            run.elapsedMs = Math.max(1, new Date().getTime() - Number(run.startedAt));
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
            _root.发布消息("返回书架未能打开，请再次选择结束旅程。");
        }
    }
    /** 只有当前槽位的书中关卡走房间；普通角色的医务室及任务返回规则保持原样。 */
    public static function isBookStageContext():Boolean {
        var run:Object = _root._saveExt.bookRun;
        return run != null && run.slot === String(_root.savePath)
            && run.bookId === BookDefinition.get().id && _root.当前关卡名 === BookDefinition.get().stageName;
    }
    public static function returnFrame(fallback) {
        return isBookStageContext() ? "房间" : fallback;
    }
}
