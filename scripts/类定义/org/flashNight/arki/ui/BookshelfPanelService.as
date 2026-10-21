import org.flashNight.neur.Server.SaveManager;
import org.flashNight.arki.ui.PanelRequestEnvelope;
import org.flashNight.neur.Event.EventBus;
import org.flashNight.gesh.object.PersistedSnapshot;
import org.flashNight.arki.item.RewardStashService;
import org.flashNight.arki.item.PlayerAssetTransaction;
import org.flashNight.arki.scene.StageRunSession;
import org.flashNight.arki.scene.StageReturnFlow;

/** 书架会话与覆盖过场中的角色权威切换。Web 不持有存档正文或奖励数值。 */
class org.flashNight.arki.ui.BookshelfPanelService {
    private static var _installed:Boolean = false;
    private static var _seq:Number = 0;
    private static var _active:Object;
    private static var _records:Object = {};
    private static var _order:Array = [];
    private static var _job:Object;
    private static var _lastAccepted:Object;
    private static var _arrivalOpen:Object;
    private static var _json:LiteJSON;
    private static var _boundaryFallback:String = "";

    public static function install():Void {
        if (_installed) return;
        _installed = true;
        _root.gameCommands["openBookshelf"] = function(p) { org.flashNight.arki.ui.BookshelfPanelService.openPanel(); };
        _root.gameCommands["bookshelfSnapshot"] = function(p) { org.flashNight.arki.ui.BookshelfPanelService.handle("snapshot", p); };
        _root.gameCommands["bookshelfCommit"] = function(p) { org.flashNight.arki.ui.BookshelfPanelService.handle("commit", p); };
        _root.gameCommands["bookshelfQuery"] = function(p) { org.flashNight.arki.ui.BookshelfPanelService.handle("query", p); };
        _root.gameCommands["intelligenceLeeStory"] = function(p:Object):Void {
            var result:Object = org.flashNight.arki.ui.BookshelfPanelService.openLeeStory(p);
            result.task="intelligence_response"; result.callId=p.callId;
            _root.UI系统.商城WebView.sendResponse(result);
        };
        EventBus.getInstance().subscribe("SceneReady", onSceneReady, null);
        org.flashNight.arki.scene.BookRunService.install();
        org.flashNight.arki.scene.BookDefinition.load();
        org.flashNight.arki.scene.LeeTrialDefinition.load();
    }
    public static function openPanel():Boolean {
        org.flashNight.arki.scene.BookDefinition.load();
        org.flashNight.arki.scene.LeeTrialDefinition.load();
        if (org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()) return false;
        if (_root.gameworld == undefined || typeof _root.server.sendSocketMessage != "function") return false;
        if (_active != null && _active.phase == "editing") _active.phase = "expired";
        var r:Object = newSession();
        var extras:Array = [{name:"token", value:r.token}];
        if (_root._saveExt.bookRun.bookId === "lee-trial")
            extras.push({name:"view", value:"lee-result"});
        return _root.server.sendSocketMessage(PanelRequestEnvelope.build("bookshelf", "world_bookshelf", [], extras)) !== false;
    }
    /** 阅读资格取当前角色的情报与生效被动；页面传来的等级或解锁标志没有权威。 */
    public static function leeStoryUnlocked(root:Object):Boolean {
        var skill:Object=root.主角被动技能.解密;
        var intel:Object=root.收集品栏.情报;
        if(skill.启用 !== true || !(Number(skill.等级)>=5) || typeof intel.toObject!="function") return false;
        return Number(intel.toObject()["黑龙令"])>=4;
    }
    public static function openLeeStory(p:Object):Object {
        org.flashNight.arki.scene.LeeTrialDefinition.load();
        if(p.itemName!=="黑龙令" || p.pageKey!=="5") return {success:false,error:"invalid_payload"};
        // 只签发/找回能力，不打开面板、不写档。已发出的出发或整理仍用旧 token 核对，不能另开一局。
        if (_active.leeEntry === true && ((_active.kind === "play" && _active.target === "lee-trial")
                || (_active.kind === "settle" && String(_active.target).indexOf("bookrun_") == 0)))
            return {success:true, token:_active.token};
        if(!leeStoryUnlocked(_root) || _root._saveExt.bookRun!=null)
            return {success:false,error:"locked"};
        if(_root._saveExt.bookshelf.active!=null && _root._saveExt.bookshelf.active.bookId!=="lee-trial")
            return {success:false,error:"other_run_active"};
        if(!canSwitch() || _root.gameworld==undefined) return {success:false,error:"busy"};
        var r:Object=_active;
        if(r==null || !same(r) || r.phase!="editing" || r.leeEntry!==true) r=newSession();
        r.leeEntry=true;
        return {success:true, token:r.token};
    }
    private static function newSession():Object {
        var r:Object = {token:"bookshelf." + new Date().getTime() + "." + getTimer() + "." + (++_seq), phase:"editing",
            slot:String(_root.savePath), owner:StageReturnFlow.worldIdentity(_root.gameworld), slots:[]};
        _active = r; _records[r.token] = r; _order.push(r.token);
        if (_order.length > 32) { var oldest:String = String(_order.shift()); if (_records[oldest] !== _job && _records[oldest] !== _lastAccepted) delete _records[oldest]; }
        return r;
    }
    public static function handle(cmd:String, p:Object):Void {
        var result:Object = execute(cmd, p);
        result.task = "bookshelf_response"; result.callId = Number(p.callId);
        if (_json == undefined) _json = new LiteJSON();
        _root.server.sendSocketMessage(_json.stringifySafe(result));
    }
    private static function same(r:Object):Boolean {
        return r.slot === String(_root.savePath) && r.owner === StageReturnFlow.worldIdentity(_root.gameworld);
    }
    public static function execute(cmd:String, p:Object):Object {
        var token:String = typeof p.token == "string" ? p.token : "";
        if (p == null || p.v !== 1 || (cmd != "snapshot" && cmd != "commit" && cmd != "query")) return fail(cmd, token, "invalid_payload");
        if (!validPayload(cmd, p) || token == "") return fail(cmd, token, "invalid_payload");
        var r:Object = _records[token];
        if (r == null) return fail(cmd, token, "stale_token");
        if (r.phase == "editing" && (!same(r) || r !== _active)) r.phase = "expired";
        if (cmd == "snapshot" && r !== _active) return fail(cmd, token, "stale_token");
        if (cmd == "query") {
            // Host 对账未获准写入的操作时先退休令牌，迟到 commit 不能在否定回执之后生效。
            if (typeof p.reconcileKind == "string" && typeof p.reconcileTarget == "string" && (r.phase == "editing" || (r.phase == "expired" && r.kind == undefined))) {
                r.kind = p.reconcileKind; r.target = p.reconcileTarget;
                r.phase = "expired"; r.error = "not_executed";
            }
            org.flashNight.arki.scene.BookRunService.reconcileOutcome();
            if (r === _job && r.phase == "save_pending") resume(r);
            completeRetainedReturn(r);
            return project(r, cmd);
        }
        if (r.phase != "editing") {
            if (cmd == "commit" && r.phase == "expired" && r.kind == undefined) {
                // 未接纳的旧场景会话返回 exact 否定回执，不把安全拒绝误报为未知写。
                r.kind = p.kind; r.target = p.target; r.error = "not_executed";
            }
            if (cmd == "commit" && (r.kind !== p.kind || r.target !== p.target)) return fail(cmd, token, "token_conflict");
            return project(r, cmd);
        }
        if (!same(r) || r !== _active) { r.phase = "expired"; return project(r, cmd); }
        if (cmd == "snapshot") { if (p.slots instanceof Array) r.slots = p.slots; return project(r, cmd); }
        if (_job != null || !canSwitch()) return fail(cmd, token, "busy");
        var kind:String = p.kind;
        var run:Object = _root._saveExt.bookRun;
        var feature:Object = _root._saveExt.bookshelf;
        if (kind == "play") {
            if ((p.target !== "repair-campus" && p.target !== "lee-trial")
                    || typeof p.runSlot != "string" || p.runSlot.indexOf("bookrun_") != 0) return fail(cmd, token, "invalid_target");
            var trial:Boolean = p.target === "lee-trial";
            if (trial ? !org.flashNight.arki.scene.LeeTrialDefinition.ready() : !org.flashNight.arki.scene.BookDefinition.ready()) {
                if (trial) org.flashNight.arki.scene.LeeTrialDefinition.load();
                else org.flashNight.arki.scene.BookDefinition.load();
                return fail(cmd, token, "config_unavailable");
            }
            if ((trial ? r.leeEntry !== true || !leeStoryUnlocked(_root) : !unlocked())
                    || run != null || feature.active != null) return fail(cmd, token, "locked");
            r.run = {v:1, bookId:p.target, slot:p.runSlot, originSlot:r.slot,
                seed:1 + Math.floor(Math.random() * 2147483645), startedAt:new Date().getTime(), outcome:"active"};
            if (trial) {
                r.run.debug = true;
                r.run.leeLoadout = org.flashNight.arki.skill.LeeSkillLoadout.copySlots(feature.leeLoadout);
            }
            r.destination = p.runSlot;
        } else if (kind == "switch") {
            if (run != null || feature.active != null || p.target == r.slot || p.snapshot == null
                || String(p.target).indexOf("bookrun_") == 0 || p.snapshot.ext.bookRun != null) return fail(cmd, token, "invalid_target");
            r.destination = p.target; r.snapshot = PersistedSnapshot.clone(p.snapshot);
        } else if (kind == "return") {
            if (run == null || run.originSlot !== p.target || p.snapshot.ext.bookshelf.active.slot !== run.slot
                || p.snapshot.ext.bookshelf.active.originSlot !== p.target
                || p.snapshot.ext.bookshelf.active.bookId !== run.bookId) return fail(cmd, token, "invalid_target");
            org.flashNight.arki.scene.BookRunService.abandonIfActive();
            r.fromStage = StageRunSession.canReturnBookContext();
            r.result = PersistedSnapshot.clone(_root._saveExt.bookRun);
            r.destination = p.target; r.snapshot = PersistedSnapshot.clone(p.snapshot);
        } else if (kind == "settle") {
            var recovered:Object = p.snapshot.ext.bookRun;
            if (p.missingRun === true && feature.active.slot === p.target) {
                recovered = PersistedSnapshot.clone(feature.active); recovered.outcome = "abandoned";
            }
            if (run != null || feature.active.slot !== p.target || recovered.slot !== p.target
                || recovered.originSlot !== r.slot || recovered.seed !== feature.active.seed
                || recovered.bookId !== feature.active.bookId
                || (r.leeEntry === true && recovered.bookId !== "lee-trial")
                || (recovered.bookId !== "repair-campus" && recovered.bookId !== "lee-trial")) return fail(cmd, token, "invalid_target");
            r.result = PersistedSnapshot.clone(recovered);
        } else return fail(cmd, token, "invalid_payload");
        if (kind != "settle" && SaveManager.getInstance().settingsProtocolV2()) {
            if (!SaveManager.registerSettingsDestination(p.settingsAuthority, r.destination)
                    || !SaveManager.registerSettingsDestination(p.settingsRollbackAuthority, r.slot)) return fail(cmd, token, "settings_recovery_required");
        }
        r.kind = kind; r.target = p.target; _job = r; _lastAccepted = r;
        if (kind == "play") {
            r.phase = "save_pending"; r.waitFor = "entry";
            if (!RewardStashService.begin(token + ".entry", {source:"bookshelf", reason:"book_enter"}, entryResolved, r)) {
                _job = null; r.phase = "editing"; return fail(cmd, token, "busy");
            }
            if (_root._saveExt.bookshelf == null) _root._saveExt.bookshelf = {};
            _root._saveExt.bookshelf.active = PersistedSnapshot.clone(r.run);
            RewardStashService.end("book.entry|" + r.run.slot, {success:true}, "bookshelf.switch");
            if (r.entrySaved === true) beginFade(r);
        } else if (kind == "settle") settle(r);
        else beginFade(r);
        return project(r, cmd);
    }
    private static function entryResolved(committed:Boolean, r:Object):Boolean {
        r.entrySaved = committed;
        if (!committed) { r.phase = "expired"; r.error = "save_failed"; _job = null; }
        return true;
    }
    private static function resume(r:Object):Void {
        var save:SaveManager = SaveManager.getInstance();
        var op:String = save.rewardCommitOperationId();
        if (op != "") {
            if (op !== r.token + ".entry" && op !== r.token + ".reward") return;
            save.resolveRewardCommit(op);
        }
        if (r.phase != "save_pending" || save.hasRewardCommitPending()) return;
        if (r.waitFor == "entry" && r.entrySaved === true) beginFade(r);
        else if (r.waitFor == "fence") beginFade(r);
        else if (r.waitFor == "reward" && r.rewardSaved !== true) settle(r);
    }
    private static function beginFade(r:Object):Void {
        if (r !== _job) return;
        if (!SaveManager.getInstance().flushBeforeTransition("bookshelf.switch")) {
            r.phase = "save_pending"; r.waitFor = "fence"; return;
        }
        r.phase = "switching";
        var frame:String = r.kind == "play" ? "wuxianguotu_1" : "房间";
        if (_root.淡出动画.淡出跳转帧(frame) !== true) {
            r.phase = "save_pending"; r.waitFor = "fence";
        } else if (r.fromStage === true) {
            // 淡出接纳后才释放旧关卡；临时战报由返回后的书籍结果替代。
            StageRunSession.dismissParallelReport(String(StageRunSession.getRunAuthority().runId));
            StageRunSession.completeReturnAttempt();
            var manager:org.flashNight.arki.scene.StageManager = org.flashNight.arki.scene.StageManager.getInstance();
            try { manager.clear(); } catch (clearError) { trace("[Bookshelf] stage cleanup failed: " + clearError); }
            // 与正规返回相同：附属清理失败不能把已接纳的过场留在战斗态。
            manager.isActive = false;
            _root.当前为战斗地图 = false;
            _root.关卡类型 = "";
            try {
                _root.关卡结束界面._visible = false;
                _root.关卡结束界面.关卡是否结束 = false;
            } catch (reportError) { trace("[Bookshelf] report projection failed: " + reportError); }
            try { _root.soundEffectManager.stopBGMForTransition(); }
            catch (bgmError) { trace("[Bookshelf] BGM transition failed: " + bgmError); }
        }
    }
    /** 在根跳图函数内、旧世界已销毁后调用。绝不在旧 actor 的 onUnload 之前换槽。 */
    public static function applyAtSceneBoundary(targetFrame):Boolean {
        var r:Object = _job;
        if (r == null || r.phase != "switching") return true;
        var save:SaveManager = SaveManager.getInstance();
        if (r.adopted === true) {
            if (r.kind != "play" || r.entryPrepared === true) return true;
            // 加载失败页的明确返回才恢复原角色；重试只继续这一次接纳，不再次换档。
            if (targetFrame == "房间") {
                if (!save.flushBeforeTransition("bookshelf.switch")
                        || !save.replacePlayerContext(r.slot, r.before, null)) return false;
                r.phase = "expired"; r.error = "entry_cancelled"; r.before = null; _job = null;
                return true;
            }
            return prepareBookEntry(r);
        }
        if (String(_root.savePath) !== r.slot || !save.flushBeforeTransition("bookshelf.switch")) {
            r.phase = "save_pending"; r.waitFor = "fence"; return false;
        }
        r.before = PersistedSnapshot.clone(save.packGameState());
        if (!save.replacePlayerContext(r.destination, r.snapshot, r.kind == "play" ? r.run : null)) {
            // 当前旧世界已经销毁；恢复的仍是刚刚持久化的原档，重新加载房间。
            if (!save.replacePlayerContext(r.slot, r.before, null)) {
                _root.允许存档 = false;
                r.phase = "save_pending"; r.waitFor = "restore"; r.error = "context_load_failed";
                return false;
            }
            r.error = "context_load_failed";
            if (r.kind == "return") { r.restored = true; r.adopted = true; r.phase = "switching"; }
            else { r.phase = "expired"; _job = null; }
            _boundaryFallback = "房间";
            return true;
        }
        r.adopted = true; r.snapshot = null;
        if (r.kind == "play") return prepareBookEntry(r);
        r.before = null;
        if (r.kind == "return") settle(r);
        return true;
    }
    /** 接纳失败恢复原档时只改本次目的地，不能带原角色误入书中战场。 */
    public static function takeBoundaryFrame(fallback) {
        if (_boundaryFallback == "") return fallback;
        var frame:String = _boundaryFallback; _boundaryFallback = "";
        return frame;
    }
    private static function prepareBookEntry(r:Object):Boolean {
        r.preparingEntry = true;
        var ready:Boolean = org.flashNight.arki.scene.BookRunService.prepareAtSceneBoundary();
        r.preparingEntry = false;
        if (!ready) return false;
        r.entryPrepared = true; r.before = null;
        return true;
    }
    /** 只在同步准备窗口内授予转场中 admission；不是可由面板传入的 allow 标志。 */
    public static function isPreparingBookEntry(slot:String):Boolean {
        var r:Object = _job;
        var run:Object = _root._saveExt.bookRun;
        return r != null && r.kind == "play" && r.phase == "switching" && r.adopted === true
            && r.preparingEntry === true && r.entryPrepared !== true && r.arrived !== true
            && slot === String(_root.savePath) && slot === r.destination && run.slot === slot
            && run.originSlot === r.slot && run.seed === r.run.seed && run.outcome == "active"
            && run.bookId === r.run.bookId && _root.gameworld._parent == undefined;
    }
    private static function settle(r:Object):Void {
        var result:Object = r.result;
        var state:Object = _root._saveExt.bookshelf;
        if (state.active.slot !== result.slot || result.originSlot !== String(_root.savePath)
            || state.active.seed !== result.seed || state.active.bookId !== result.bookId) { r.phase = "expired"; r.error = "context_changed"; _job = null; return; }
        r.waitFor = "reward"; r.phase = "save_pending";
        r.previousFeature = PersistedSnapshot.clone(state);
        if (!RewardStashService.begin(r.token + ".reward", {source:"level_reward", reason:"book_reward",
                operationId:"book.reward." + result.slot, mergeScope:"operation"}, rewardResolved, r)) return;
        state = _root._saveExt.bookshelf;
        var trial:Boolean = result.bookId === "lee-trial";
        var quote:Object = trial ? {sp:0, reason:"debug"} : org.flashNight.arki.scene.BookRunRules.reward(result, state);
        var record:Object = org.flashNight.arki.scene.BookRunRules.resultRecord(result, quote, new Date().getTime());
        if (trial) {
            record.debug = true;
            state.lastTrialRecord = record;
            state.leeLoadout = org.flashNight.arki.skill.LeeSkillLoadout.copySlots(result.leeLoadout);
        } else {
            _root.技能点数 += quote.sp;
            state.firstClear = quote.firstClear; state.bestTier = quote.bestTier;
            state.bestMs = quote.bestMs;
            state.clears = Number(state.clears || 0) + (quote.sp > 0 ? 1 : 0);
            state.lastReward = quote.sp;
            var history:Array = [record];
            if (state.history instanceof Array) {
                for (var h:Number = 0; h < state.history.length && history.length < 20; h++) {
                    if (state.history[h].runId !== result.slot) history.push(state.history[h]);
                }
            }
            state.history = history;
        }
        state.lastRun = result.slot; state.active = null;
        // 与 SP 和领取凭据一起提交；失败/未知保存不会提前播报到账。
        if (quote.sp > 0) PlayerAssetTransaction.recordEffect("gain", "skillpoint", "技能点", quote.sp,
            {source:"level_reward", reason:"book_reward", operationId:"book.reward." + result.slot, mergeScope:"operation"});
        r.reward = quote.sp;
        RewardStashService.end("book.reward|" + result.slot, {success:true, sp:quote.sp}, "bookshelf.reward");
    }
    private static function rewardResolved(committed:Boolean, r:Object):Boolean {
        r.rewardSaved = committed;
        if (committed) { r.phase = r.adopted === true ? "switching" : "applied"; if (r.phase == "applied") _job = null; }
        return true;
    }
    private static function completeRetainedReturn(r:Object):Void {
        if (r !== _job || r.kind != "return" || (r.rewardSaved !== true && r.restored !== true) || r.arrived !== true
            || (r.restored === true ? r.slot : r.destination) !== String(_root.savePath) || r.arrivalOwner !== StageReturnFlow.worldIdentity(_root.gameworld)
            || org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()
            || _root.淡出动画.__returnFadeActive === true || _root.场景转换中 === true) return;
        r.phase = r.restored === true ? "expired" : "applied"; _job = null;
    }
    private static function onSceneReady(world:Object, token:String, identity:Object):Void {
        if (world !== _root.gameworld || identity == null || identity !== StageReturnFlow.worldIdentity(world)) return;
        var r:Object = _job;
        if (r != null && r.adopted === true && (r.restored === true ? r.slot : r.destination) === String(_root.savePath)) {
            r.arrived = true; r.arrivalOwner = identity;
            if (r.kind != "return") { r.phase = "applied"; _job = null; }
            // 返回书中挑战保留原 Web 实例，查询到终态后签发原角色的新能力。
            if (r.kind == "switch") {
                _arrivalOpen = {slot:String(_root.savePath), owner:identity};
                _root.帧计时器.添加单次任务(openAfterArrival, 1);
            }
        }
    }
    private static function openAfterArrival():Void {
        var context:Object = _arrivalOpen;
        if (context == null) return;
        if (context.slot !== String(_root.savePath) || context.owner !== StageReturnFlow.worldIdentity(_root.gameworld)) {
            _arrivalOpen = null; return;
        }
        // 换回原角色和常驻换档也必须等真实揭幕尾帧；第 17 帧只释放初始化锁。
        if (org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()
                || StageRunSession.hasUnpresentedSettlementReport() || _root._webPanelPauseLease != undefined
                || _root.淡出动画.__returnFadeActive === true || _root.场景转换中 === true) {
            _root.帧计时器.添加单次任务(openAfterArrival, 1); return;
        }
        _arrivalOpen = null;
        openPanel();
    }
    private static function unlocked():Boolean {
        return !isNaN(Number(_root.tasks_finished[21])) && Number(_root.tasks_finished[21]) >= 1;
    }
    private static function canSwitch():Boolean {
        return SaveManager.getInstance().settingsWriteAllowed() && _root.允许存档 === true && (StageRunSession.canNavigateAwayFromStage() || StageRunSession.canReturnBookContext())
            && !org.flashNight.arki.scene.BookRunService.hasUnsettledOutcome()
            && !SaveManager.getInstance().hasRewardCommitPending() && PlayerAssetTransaction.current() == null
            && !org.flashNight.arki.ui.SceneTransitionService.isPresentationPending()
            && _root.淡出动画.__returnFadeActive !== true && _root.场景转换中 !== true;
    }
    private static function project(r:Object, cmd:String):Object {
        var run:Object = _root._saveExt.bookRun, feature:Object = _root._saveExt.bookshelf;
        if (_job != null && _job.waitFor == "reward" && _job.rewardSaved !== true
                && _job.previousFeature != null) feature = _job.previousFeature;
        // 终态回执仍归旧 token；新的编辑能力独立签发，不能把已完成 token 重新变可写。
        var returned:Boolean = r.kind == "return" && (r.phase == "applied" || r.restored === true && r.phase == "expired")
            && (r.restored === true ? r.slot : r.destination) === String(_root.savePath)
            && r.arrivalOwner === StageReturnFlow.worldIdentity(_root.gameworld);
        if ((r.phase == "applied" || r.phase == "expired") && _job == null && r === _active && (same(r) || returned)) {
            var fresh:Object = newSession(); fresh.slots = r.slots;
            if (r.leeEntry === true) fresh.leeEntry = true;
            r.nextToken = fresh.token;
        }
        return {v:1, operation:cmd, token:r.token, phase:r.phase, success:r.phase != "expired" && r.phase != "save_pending",
            settingsAuthorityOwner:SaveManager.getInstance().getSettingsAuthority() == null ? null : SaveManager.getInstance().getSettingsAuthority().ownerId(),
            nextToken:String(r.nextToken || ""), exitRequired:run != null && (run.outcome != "active" || StageRunSession.canReturnBookContext()),
            activeSlot:String(_root.savePath), role:String(_root.角色名), canSwitch:canSwitch() && _job == null,
            kind:String(r.kind || ""), target:String(r.target || ""),
            outcomePending:org.flashNight.arki.scene.BookRunService.hasUnsettledOutcome(),
            unlocked:unlocked(), leeEntry:r.leeEntry === true && leeStoryUnlocked(_root), inRun:run != null, originSlot:run == null ? "" : String(run.originSlot),
            bookId:run == null ? "" : String(run.bookId), pendingBookId:feature.active == null ? "" : String(feature.active.bookId),
            lastTrialRecord:feature.lastTrialRecord == null ? null : PersistedSnapshot.clone(feature.lastTrialRecord),
            runOutcome:run == null ? "" : String(run.outcome), pendingRun:feature.active == null ? "" : String(feature.active.slot),
            reward:r.rewardSaved === true ? Number(r.reward || 0) : 0, lastReward:Number(feature.lastReward || 0),
            records:{bestMs:Number(feature.bestMs || 0), clears:Number(feature.clears || 0),
                history:feature.history instanceof Array ? PersistedSnapshot.clone(feature.history) : []},
            returningResult:r.kind == "return" && r.result != null
                ? org.flashNight.arki.scene.BookRunRules.resultRecord(r.result, {sp:0,reason:"pending"}, 0) : null,
            error:String(r.error || ""), slots:r.slots};
    }
    private static function validPayload(cmd:String, p:Object):Boolean {
        var allowed:Object = {v:true, token:true, task:true, action:true, callId:true};
        if (cmd == "snapshot") allowed.slots = true;
        if (cmd == "query") { allowed.reconcileKind = true; allowed.reconcileTarget = true; }
        if (cmd == "commit") {
            allowed.settingsAuthority = true; allowed.settingsRollbackAuthority = true;
            if (typeof p.kind != "string" || typeof p.target != "string" || p.target == "") return false;
            allowed.kind = true; allowed.target = true;
            if (p.kind == "play") allowed.runSlot = true;
            else if (p.kind == "switch" || p.kind == "return") allowed.snapshot = true;
            else if (p.kind == "settle") { allowed.snapshot = true; allowed.missingRun = true; }
            else return false;
        }
        for (var key:String in p) if (allowed[key] !== true) return false;
        return true;
    }
    public static function _resetForTests():Void {
        _active = null; _records = {}; _order = []; _job = null; _lastAccepted = null; _arrivalOpen = null;
        _boundaryFallback = "";
    }
    private static function fail(cmd:String, token:String, error:String):Object {
        return {v:1, operation:cmd, token:token, success:false, error:error};
    }
}
