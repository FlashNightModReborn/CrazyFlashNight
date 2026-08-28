import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.LootContainerService;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.arki.unit.UnitComponent.Targetcache.TargetCacheManager;

/**
 * 一次 GameStage 的权威会话。
 *
 * outcome 与 life 是两条正交状态轴：通关后仍可死亡，死亡后也能选择继续关卡。
 * C# 只渲染快照并回送带 run/revision 的 intent；复活扣币、返回基地、奖励随机化与
 * 领取事务始终由 AS2 决定。Web 只接收返回基地后的只读战报和 Loot authority。
 */
class org.flashNight.arki.scene.StageRunSession {
    private static var MAX_KILL_TYPES:Number = 96;
    private static var MAX_ITEM_FLOW_TYPES:Number = 96;
    private static var MAX_REWARD_SLOTS:Number = 64;
    private static var REWARD_COLUMNS:Number = 4;
    // AVM1 random() 的跨度是有符号 32 位整数；safe integer 仍可能在这里回绕。
    private static var MAX_RANDOM_SPAN:Number = 2147483647;

    private static var _installed:Boolean = false;
    private static var _runSeq:Number = 0;
    private static var _run:Object = null;
    private static var _processedIntents:Object = {};
    private static var _preparedInventory:ArrayInventory = null;
    private static var _preparedReport:Object = null;
    private static var _settlementStarted:Boolean = false;
    private static var _returnRequested:Boolean = false;
    private static var _deliverAfterSettlement:Boolean = false;
    // 场景淡出与 StageManager.initialize 之间存在异步窗口。入口必须先取得唯一 reservation，
    // initialize/begin 再按目标关卡消费；这样第二个入口不能在旧 run 尚未建立时重复获准。
    private static var _stageStartSeq:Number = 0;
    private static var _stageStartReservation:Object = null;
    private static var _testDeliverableResolver:Function = null;
    private static var _testDeliverableNavigator:Function = null;

    public static function install():Void {
        if (_installed) return;
        if (_root.gameCommands == undefined) _root.gameCommands = {};
        _root.gameCommands["stageOutcomeAction"] = function(params:Object):Void {
            org.flashNight.arki.scene.StageRunSession.handleAction(params);
        };
        _root.gameCommands["stageOutcomeSync"] = function(params:Object):Void {
            org.flashNight.arki.scene.StageRunSession.handleSync(params);
        };
        _installed = true;
    }

    /** 新关卡只能在上一轮已经正规返回并终结结算时开始，防止 run/奖励对象被覆盖。 */
    public static function begin(stageName:String, difficulty:String, stageStartToken:String):Boolean {
        install();
        var name:String = safeText(stageName, 96, "未知关卡");
        var mode:String = safeText(difficulty, 48, "未知难度");
        var blockReason:String = getStageStartBlockReasonIgnoringReservation();
        if (blockReason != "") {
            trace("[StageRunSession] " + blockReason + " blocks a new stage");
            return false;
        }
        var suppliedToken:String = String(stageStartToken || "");
        if (_stageStartReservation == null && suppliedToken != "") {
            trace("[StageRunSession] stale_or_cancelled_stage_start_token");
            return false;
        }
        if (_stageStartReservation != null) {
            if (suppliedToken == "" || suppliedToken !== _stageStartReservation.token) {
                trace("[StageRunSession] missing_or_mismatched_stage_start_token");
                return false;
            }
            var expectedStage:String = String(_stageStartReservation.stageName || "");
            var expectedDifficulty:String = String(_stageStartReservation.difficulty || "");
            if (expectedStage != "" && expectedStage != name) {
                trace("[StageRunSession] stage_start_target_mismatch expected="
                    + expectedStage + " actual=" + name);
                return false;
            }
            if (expectedDifficulty != "" && expectedDifficulty != mode) {
                trace("[StageRunSession] stage_start_difficulty_mismatch expected="
                    + expectedDifficulty + " actual=" + mode);
                return false;
            }
            _stageStartReservation = null;
        }
        _runSeq++;
        _run = {
            v:1,
            runId:"run." + getTimer() + "." + _runSeq,
            revision:1,
            stageName:name,
            difficulty:mode,
            outcome:"active",
            life:"alive",
            activeFrames:0,
            totalKills:0,
            kills:[],
            killsByKey:{},
            omittedKillTypes:0,
            omittedKillKeys:{},
            totalItemGains:0,
            totalItemLosses:0,
            itemFlows:[],
            itemFlowsByKey:{},
            omittedItemFlowTypes:0,
            omittedItemFlowKeys:{},
            rewardRollOmissions:0,
            settlement:"none",
            remainingRewards:0
        };
        _processedIntents = {};
        _preparedInventory = null;
        _preparedReport = null;
        _settlementStarted = false;
        _returnRequested = false;
        _deliverAfterSettlement = false;
        pushState();
        return true;
    }

    public static function canStartStage():Boolean {
        return getStageStartBlockReason() == "";
    }

    /** 新关卡 admission 的稳定错误码；UI 只展示，AS2 入口仍须重新裁决。 */
    public static function getStageStartBlockReason():String {
        if (_stageStartReservation != null) return "stage_start_pending";
        return getStageStartBlockReasonIgnoringReservation();
    }

    /**
     * 为即将发生的异步 stage load 保留唯一席位。返回空串表示被拒绝；token 仅用于
     * 同步失败时 exact cancel，成功路径由 begin 按 stageName 消费。
     */
    public static function reserveStageStart(
            source:String, stageName:String, difficulty:String):String {
        install();
        if (getStageStartBlockReason() != "") return "";
        var normalizedStageName:String = safeText(stageName, 96, "");
        if (normalizedStageName == "") return "";
        _stageStartSeq++;
        var token:String = "stage.start." + getTimer() + "." + _stageStartSeq;
        _stageStartReservation = {
            token:token,
            source:safeText(source, 64, "unknown"),
            stageName:normalizedStageName,
            difficulty:safeText(difficulty, 48, "")
        };
        return token;
    }

    /** 仅 exact token 可撤销尚未被 begin 消费的 reservation。 */
    public static function cancelStageStart(token:String):Boolean {
        if (_stageStartReservation == null || token == undefined
                || token == "" || token !== _stageStartReservation.token) return false;
        _stageStartReservation = null;
        return true;
    }

    /** 异步 loader 在应用 XML/初始化 StageManager 前复核 exact reservation。 */
    public static function isStageStartReservationValid(token:String):Boolean {
        return token != undefined && token != "" && _stageStartReservation != null
            && token === _stageStartReservation.token;
    }

    /** 窄 host 例外可同时核验 exact token、来源与目标，防伪造 allow 标志。 */
    public static function matchesStageStartReservation(
            token:String, source:String, stageName:String):Boolean {
        return isStageStartReservationValid(token)
            && String(_stageStartReservation.source || "") == String(source || "")
            && String(_stageStartReservation.stageName || "") == String(stageName || "");
    }

    /**
     * 离开当前场景的统一硬门。正规 _root.返回基地 不走此门，而是先调用
     * onReturnBaseStarted；地图/选关/外交地图等旁路必须在副作用前调用。
     */
    public static function getSceneExitBlockReason():String {
        if (_stageStartReservation != null) return "stage_start_pending";
        if (_run != null && !isRunTerminal()) {
            return _returnRequested ? "pending_stage_settlement" : "stage_run_active";
        }
        if (_preparedInventory != null || LootContainerService.hasStageSettlementPending()) {
            return "pending_stage_settlement";
        }
        if (_root.当前为战斗地图 === true) return "battle_map";
        return "";
    }

    public static function canNavigateAwayFromStage():Boolean {
        return getSceneExitBlockReason() == "";
    }

    /** StageManager.clear 只能发生在无 run 或正规返回已经冻结 run 之后。 */
    public static function canClearStageManager():Boolean {
        return _stageStartReservation == null && (_run == null || _returnRequested);
    }

    private static function getStageStartBlockReasonIgnoringReservation():String {
        if (_run != null && !isRunTerminal()) {
            return _returnRequested ? "pending_stage_settlement" : "stage_run_active";
        }
        if (_preparedInventory != null || LootContainerService.hasStageSettlementPending()) {
            return "pending_stage_settlement";
        }
        // 没有 run 不代表处于基地：斗兽标定和旧战斗图可明确不创建
        // StageRunSession。此时仍必须拒绝第二个关卡入场。
        if (_root.斗兽标定模式 === true) return "calibration_active";
        if (_root.当前为战斗地图 === true) return "battle_map";
        return "";
    }

    private static function isRunTerminal():Boolean {
        if (_run == null) return true;
        if (!_returnRequested) return false;
        var settlement:String = String(_run.settlement || "");
        return settlement == "claimed" || settlement == "abandoned" || settlement == "error";
    }

    /** StageManager 每个未暂停的游戏帧调用；这是战报时间的唯一时钟。 */
    public static function tick():Void {
        if (_run == null || _returnRequested || _run.outcome == "retreat") return;
        var current:Number = Number(_run.activeFrames);
        if (isNaN(current) || current < 0) current = 0;
        if (current < 9007199254740991) _run.activeFrames = current + 1;
    }

    public static function finish(outcome:String):Void {
        if (_run == null || (outcome != "victory" && outcome != "failure")) return;
        if (_run.outcome != "active") return;
        _run.outcome = outcome;
        bumpRevision();
        pushState();
    }

    /** 死亡检测可能每帧重入；只有 alive -> dead 会推进一次状态。 */
    public static function onHeroDeath():Void {
        if (_run == null || _returnRequested || _run.life != "alive") return;
        _run.life = "dead";
        bumpRevision();
        pushState();
    }

    public static function onHeroRespawn(target:MovieClip):Void {
        if (_run == null || _run.life == "alive") return;
        var hero:MovieClip;
        try { hero = TargetCacheManager.findHero(); } catch (findError) { hero = undefined; }
        // RespawnEventComponent 也服务佣兵/敌人。只有当前控制主角的同一 MovieClip
        // 且 HP 已真实恢复，才能推进玩家 life 轴。
        if (hero == undefined || target == undefined || target !== hero
                || isNaN(Number(target.hp)) || Number(target.hp) <= 0) return;
        _run.life = "alive";
        bumpRevision();
        pushState();
    }

    public static function canRequestRevive():Boolean {
        return _run != null && _run.life == "dead" && !_returnRequested;
    }

    /** 发布击杀播报时把同一规范化投影记入本轮；结算前仍允许通关后的继续击杀。 */
    public static function recordKillProjection(projection:Object):Void {
        if (_run == null || _returnRequested || projection == null) return;
        var key:String = safeText(String(projection.key), 128, "");
        if (key.length == 0) return;
        _run.totalKills = Number(_run.totalKills) + 1;
        var mapKey:String = "$" + key;
        var entry:Object = _run.killsByKey[mapKey];
        if (entry != undefined) {
            entry.count = Number(entry.count) + 1;
            var incomingElite:Number = safeWhole(projection.eliteLevel, 0, 16, 0);
            if (incomingElite > Number(entry.eliteLevel)) entry.eliteLevel = incomingElite;
            return;
        }
        if (_run.kills.length >= MAX_KILL_TYPES) {
            if (_run.omittedKillKeys[mapKey] !== true) {
                _run.omittedKillKeys[mapKey] = true;
                _run.omittedKillTypes = Number(_run.omittedKillTypes) + 1;
            }
            return;
        }
        entry = {
            key:key,
            displayName:safeText(String(projection.displayName), 96, key),
            iconName:safeText(String(projection.iconName), 128, ""),
            doll:copyDoll(projection.doll),
            eliteLevel:safeWhole(projection.eliteLevel, 0, 16, 0),
            count:1
        };
        _run.killsByKey[mapKey] = entry;
        _run.kills.push(entry);
    }

    /**
     * 与左下物资播报消费同一份已规范化事实。这里只做有界汇总，不接管资产写入，
     * 也不因 socket 是否在线而丢失本轮统计；开始返回基地后拒绝结算领取产生的回流。
     */
    public static function recordAssetProjection(projection:Object):Void {
        if (_run == null || _returnRequested || projection == null) return;
        var direction:String = String(projection.direction);
        var kind:String = String(projection.kind);
        if ((direction != "gain" && direction != "loss")
                || !isReportAssetKind(kind)) return;
        var count:Number = Number(projection.count);
        if (!isWhole(count) || count <= 0 || count > 9007199254740991) return;
        if (direction == "gain") {
            _run.totalItemGains = safeAddCount(Number(_run.totalItemGains), count);
        } else {
            _run.totalItemLosses = safeAddCount(Number(_run.totalItemLosses), count);
        }

        var itemKey:String = safeText(String(projection.itemKey), 128, "");
        if (itemKey.length == 0) return;
        var tier:String = safeText(String(projection.tier), 48, "");
        var source:String = safeText(String(projection.source), 48, "unknown");
        var reason:String = safeText(String(projection.reason), 64, "");
        var mapKey:String = "$" + direction + "|" + kind + "|" + itemKey
            + "|" + tier + "|" + source + "|" + reason;
        var entry:Object = _run.itemFlowsByKey[mapKey];
        if (entry != undefined) {
            entry.count = safeAddCount(Number(entry.count), count);
            return;
        }
        if (_run.itemFlows.length >= MAX_ITEM_FLOW_TYPES) {
            if (_run.omittedItemFlowKeys[mapKey] !== true) {
                _run.omittedItemFlowKeys[mapKey] = true;
                _run.omittedItemFlowTypes = Number(_run.omittedItemFlowTypes) + 1;
            }
            return;
        }
        entry = {
            direction:direction,
            kind:kind,
            itemKey:itemKey,
            displayName:safeText(String(projection.name), 96, itemKey),
            iconName:safeText(String(projection.icon), 128, ""),
            tier:tier,
            source:source,
            reason:reason,
            count:count
        };
        _run.itemFlowsByKey[mapKey] = entry;
        _run.itemFlows.push(entry);
    }

    /** 设置页兜底与 C# 按钮都必须走这一条扣币 + respawn 事件路径。 */
    public static function requestReviveLocal(source:String):Object {
        if (_run == null) return {success:false, error:"revive_unavailable"};
        if (_run.life != "dead") return {success:false, error:"actor_alive"};
        if (_returnRequested) return {success:false, error:"return_in_progress"};
        if (_root.限制系统 != undefined && _root.限制系统.DisableResurrection == true) {
            pushState();
            return {success:false, error:"resurrection_restricted"};
        }
        var hero:MovieClip;
        try { hero = TargetCacheManager.findHero(); } catch (findError) { hero = undefined; }
        if (hero != undefined && !isNaN(Number(hero.hp)) && Number(hero.hp) > 0) {
            // 兼容外部恢复先于状态回告的路径：只校正 life，不再扣复活币。
            onHeroRespawn(hero);
            return {success:false, error:"actor_alive"};
        }
        if (hero == undefined || hero.dispatcher == undefined
                || typeof hero.dispatcher.publish != "function") {
            pushState();
            return {success:false, error:"revive_target_unavailable"};
        }

        _run.life = "reviving";
        bumpRevision();
        pushState();
        var coinsBefore:Number = reviveCoinCount();
        var spendContext:Object = {
            source:"player_revive",
            reason:safeText(source, 48, "stage_outcome")
        };
        var submitAccepted:Boolean = false;
        try {
            submitAccepted = ItemUtil.singleSubmit("复活币", 1, spendContext);
        } catch (submitError) {
            // ItemUtil 的同步 listener 可能在材料已真实扣除后抛错；以 before/after
            // 资产事实收敛，既不重复扣币，也不把已扣币玩家永久留在 reviving。
            submitAccepted = false;
        }
        var coinsAfterSpend:Number = reviveCoinCount();
        var spentExactlyOne:Boolean = coinsBefore >= 1
            && coinsAfterSpend == coinsBefore - 1;
        if (!submitAccepted && !spentExactlyOne) {
            _run.life = "dead";
            bumpRevision();
            pushState();
            return {success:false, error:coinsBefore < 1
                ? "no_revive_coin" : "revive_asset_failed"};
        }
        if (submitAccepted && !spentExactlyOne) {
            _run.life = "dead";
            bumpRevision();
            pushState();
            return {success:false, error:"revive_asset_ambiguous"};
        }

        try {
            // RespawnEventComponent 的回调契约是第一个参数为目标单位。EventBus v3
            // 的 scope 只负责绑定 this，零参数 publish 不会再把 scope 注入形参；
            // 因此必须与 ZeroHPDetector 一样显式携带 hero。
            hero.dispatcher.publish("respawn", hero);
        } catch (publishError) {
            // 下面按实际 HP / life 收敛；异常本身不决定复活是否发生。
        }
        // dispatcher 可以在已经恢复 HP / 发布 respawn 后才抛错；生命事实优先于
        // 回调返回形态，否则会错误退款并重新标死一个已经复活的主角。
        if (Number(hero.hp) > 0) {
            if (_run.life != "alive") onHeroRespawn(hero);
            return {success:true, error:"", reviveCoins:reviveCoinCount()};
        }

        // 同步 respawn 未生效时返还本次扣除；不直接改 HP，避免制造第二复活语义。
        try {
            ItemUtil.singleAcquire("复活币", 1, {
                source:"player_revive", reason:"respawn_dispatch_rollback"
            });
        } catch (refundError) {
            // 同样按材料 before/after 判定退款是否真实落地。
        }
        var refundExact:Boolean = reviveCoinCount() == coinsBefore;
        _run.life = "dead";
        bumpRevision();
        pushState();
        return {success:false, error:refundExact
            ? "respawn_dispatch_failed" : "respawn_dispatch_rollback_failed"};
    }

    public static function requestReturnBaseLocal(source:String):Object {
        if (_run == null || _returnRequested
                || (_run.life != "dead" && _run.outcome == "active")) {
            return {success:false, error:"return_base_unavailable"};
        }
        if (typeof _root.返回基地 != "function") {
            return {success:false, error:"return_base_unavailable"};
        }
        try {
            var accepted = _root.返回基地();
            if (accepted === false) return {success:false, error:"settlement_prepare_failed"};
        } catch (returnError) {
            return {success:false, error:"return_base_failed"};
        }
        return {success:true, error:""};
    }

    /**
     * 胜利后的便利入口：仍走完整返回基地与奖励结算，只登记“结算关闭后前往交付”。
     * 目标不由 C# 携带；AS2 在登记时和最终跳转前都从当前已达成任务重新解析。
     */
    public static function requestReturnDeliverableLocal(source:String):Object {
        if (_run == null || _returnRequested || _run.outcome != "victory"
                || _run.life != "alive" || _run.settlement != "none") {
            return {success:false, error:"return_deliverable_unavailable"};
        }
        var deliverable:Object = resolveDeliverableState();
        if (deliverable == null || deliverable.returnNavigable !== true
                || deliverable.hotspotId == undefined
                || String(deliverable.hotspotId).length == 0) {
            return {success:false, error:"deliverable_unavailable"};
        }

        _deliverAfterSettlement = true;
        var returned:Object = requestReturnBaseLocal(source);
        if (returned == null || returned.success !== true)
            _deliverAfterSettlement = false;
        return returned;
    }

    /** 所有返回基地入口先调用；幂等冻结战报和唯一奖励物件，再开始场景跳转。 */
    public static function onReturnBaseStarted():Boolean {
        // stage XML/TimePool 尚未确认时不能边返回基地边让迟到回调
        // 建立新 run。保留 exact reservation，由原入场链成功消费或失败撤销。
        if (_stageStartReservation != null) return false;
        // 斗兽标定等明确不创建 StageRunSession 的旧流程仍可沿用返回基地；
        // requestReturnBaseLocal 本身会在无会话时拒绝原生按钮意图。
        if (_run == null) return true;
        // 同一轮已经开始返回（包括奖励已领取/放弃后的终态）时只作幂等确认。
        // _preparedInventory 在终态会释放，不能因此重新随机化一次通关奖励。
        if (_returnRequested) return true;
        if (_run.outcome == "active") {
            _run.outcome = "retreat";
            bumpRevision();
        }
        if (!prepareSettlement()) return false;
        _returnRequested = true;
        bumpRevision();
        pushState();
        return true;
    }

    public static function prepareSettlement():Boolean {
        if (_preparedInventory != null && _preparedReport != null) return true;
        if (_run == null) return false;
        if (_run.outcome == "active") {
            _run.outcome = "retreat";
            bumpRevision();
        }

        var rolled:Object = materializeRewards(_run.outcome == "victory"
            ? _root.关卡可获得奖励品 : []);
        if (rolled == null || rolled.inventory == null) return false;
        _run.rewardRollOmissions = Number(rolled.omissions);
        _run.remainingRewards = Number(rolled.inventory.size());
        _run.settlement = "prepared";
        _preparedInventory = rolled.inventory;
        _preparedReport = buildReport();
        bumpRevision();
        pushState();
        return true;
    }

    /** 基地人物真正加载完成后才打开 Web；转场和 gameworld cleanup 阶段没有 Web lease。 */
    public static function onSceneReady():Void {
        if (_run == null || !_returnRequested || _preparedInventory == null
                || _preparedReport == null || _root.当前为战斗地图 === true) return;
        if (_settlementStarted) return;
        var begun:Object = LootContainerService.beginStageSettlement(
            _preparedInventory, _preparedReport);
        if (begun == null || begun.success !== true) {
            _run.settlement = "rewards_pending";
            bumpRevision();
            pushState();
            return;
        }
        _settlementStarted = true;
        _run.settlement = "web_active";
        _run.remainingRewards = Number(_preparedInventory.size());
        bumpRevision();
        pushState();
        LootContainerService.requestOpenPanel();
    }

    /** LootContainerService 的唯一回告；普通关闭保留奖励并显式暴露“继续领取”。 */
    public static function onSettlementState(state:String, remaining:Number):Void {
        if (_run == null) return;
        var settlement:String;
        if (state == "LOOT_ACTIVE") settlement = "web_active";
        else if (state == "LOOT_SUSPENDED") settlement = "rewards_pending";
        else if (state == "CONSUMED") settlement = "claimed";
        else if (state == "ABANDONED") settlement = "abandoned";
        else if (state == "EXPIRED") settlement = "error";
        else return;
        _run.settlement = settlement;
        _run.remainingRewards = safeWhole(remaining, 0, MAX_REWARD_SLOTS, 0);
        bumpRevision();
        pushState();
        if (settlement == "claimed" || settlement == "abandoned" || settlement == "error") {
            _preparedInventory = null;
            _preparedReport = null;
            tryCompletePendingDeliverNavigation();
        }
    }

    /**
     * Host 收齐 exact DOM/native close 证明并释放 Web pause 后调用。普通 terminal 通知
     * 发生得更早，只会留下意图；这里才允许场景导航，避免奖励面板与转场重叠。
     */
    public static function onWebPanelClosed():Void {
        tryCompletePendingDeliverNavigation();
    }

    private static function tryCompletePendingDeliverNavigation():Boolean {
        if (!_deliverAfterSettlement || _run == null) return false;
        if (_root._webPanelPauseLease != undefined
                || _root.当前为战斗地图 === true) return false;
        if (_run.settlement != "claimed" && _run.settlement != "abandoned"
                && _run.settlement != "error") return false;

        var deliverable:Object = resolveDeliverableState();
        _deliverAfterSettlement = false;
        if (deliverable == null || deliverable.navigable !== true
                || deliverable.hotspotId == undefined
                || String(deliverable.hotspotId).length == 0) return false;
        try {
            return navigateToDeliverable(String(deliverable.hotspotId));
        } catch (navigateError) {
            return false;
        }
    }

    private static function resolveDeliverableState():Object {
        if (_testDeliverableResolver != null)
            return _testDeliverableResolver();
        return org.flashNight.arki.map.MapPanelService.resolveDeliverableState();
    }

    private static function navigateToDeliverable(hotspotId:String):Boolean {
        if (_testDeliverableNavigator != null)
            return _testDeliverableNavigator(hotspotId) === true;
        return org.flashNight.arki.map.MapPanelService.navigateToHotspot(hotspotId);
    }

    private static function handleAction(params:Object):Void {
        if (!validateAction(params) || _run == null
                || params.runId !== _run.runId
                || Number(params.expectedRevision) != Number(_run.revision)) {
            pushState();
            return;
        }
        var intentId:String = String(params.intentId);
        var journalKey:String = "$" + intentId;
        if (_processedIntents[journalKey] === true) {
            pushState();
            return;
        }
        _processedIntents[journalKey] = true;
        if (params.intent === "revive") {
            requestReviveLocal("stage_outcome");
        } else if (params.intent === "return_base") {
            requestReturnBaseLocal("stage_outcome");
        } else if (params.intent === "return_deliverable") {
            requestReturnDeliverableLocal("stage_outcome");
        } else if (params.intent === "resume_rewards") {
            if (_run.settlement == "rewards_pending") {
                if (_settlementStarted) LootContainerService.resumeStageSettlement();
                else onSceneReady();
            }
        }
    }

    private static function handleSync(params:Object):Void {
        if (params == null || !hasOnlyKeys(params, ["task", "action", "v"])
                || params.task !== "cmd" || params.action !== "stageOutcomeSync"
                || params.v !== 1) return;
        pushState();
    }

    private static function validateAction(params:Object):Boolean {
        if (!hasOnlyKeys(params, ["task", "action", "v", "runId",
                "expectedRevision", "intent", "intentId"])) return false;
        return params.task === "cmd" && params.action === "stageOutcomeAction"
            && params.v === 1 && typeof params.runId == "string"
            && isSafeToken(String(params.runId), 96)
            && isWhole(params.expectedRevision) && Number(params.expectedRevision) > 0
            && (params.intent === "revive" || params.intent === "return_base"
                || params.intent === "return_deliverable"
                || params.intent === "resume_rewards")
            && typeof params.intentId == "string"
            && isSafeToken(String(params.intentId), 96);
    }

    private static function materializeRewards(config):Object {
        var source:Array = config instanceof Array ? config : [];
        var selected:Array = [];
        var omissions:Number = 0;
        var special:Boolean = false;
        try {
            special = typeof _root.是否是某网站 == "function"
                && _root.是否是某网站(["andylaw.net", "www.andylaw.net",
                    "game.andylaw.net", "crazyparkour.andylaw.net"]) == true;
        } catch (siteError) {
            special = false;
        }
        for (var i:Number = 0; i < source.length; i++) {
            var row = source[i];
            if (!(row instanceof Array) || row.length < 3) {
                omissions++;
                continue;
            }
            var name:String = normalizeRewardName(String(row[0]));
            var chance:Number = Number(row[1]);
            var maximum:Number = Number(row[2]);
            if (name.length == 0 || !ItemUtil.isItem(name)
                    || !isWhole(chance) || chance <= 0
                    || !isWhole(maximum) || maximum <= 0
                    || chance > MAX_RANDOM_SPAN || maximum > MAX_RANDOM_SPAN) {
                omissions++;
                continue;
            }
            var denominator:Number = special ? Math.floor(chance) / 2 : chance;
            if (denominator < 1) denominator = 1;
            if (random(denominator) != 0) continue;
            if (selected.length >= MAX_REWARD_SLOTS) {
                omissions++;
                continue;
            }
            var quantity:Number = random(maximum) + 1;
            var item:BaseItem = BaseItem.create(name, quantity, new Date().getTime());
            if (item == null) {
                omissions++;
                continue;
            }
            selected.push(item);
        }
        var capacity:Number = Math.max(8,
            Math.ceil(selected.length / REWARD_COLUMNS) * REWARD_COLUMNS);
        if (capacity > MAX_REWARD_SLOTS) capacity = MAX_REWARD_SLOTS;
        var inventory:ArrayInventory = new ArrayInventory(null, capacity);
        for (i = 0; i < selected.length && i < capacity; i++) {
            if (!inventory.add(i, selected[i])) omissions++;
        }
        return {inventory:inventory, omissions:omissions};
    }

    private static function buildReport():Object {
        var kills:Array = [];
        for (var i:Number = 0; i < _run.kills.length; i++) {
            var source:Object = _run.kills[i];
            kills.push({
                key:String(source.key),
                displayName:String(source.displayName),
                iconName:String(source.iconName),
                doll:copyDoll(source.doll),
                eliteLevel:Number(source.eliteLevel),
                count:Number(source.count)
            });
        }
        var itemFlows:Array = [];
        for (i = 0; i < _run.itemFlows.length; i++) {
            source = _run.itemFlows[i];
            itemFlows.push({
                direction:String(source.direction),
                kind:String(source.kind),
                itemKey:String(source.itemKey),
                displayName:String(source.displayName),
                iconName:String(source.iconName),
                tier:String(source.tier),
                source:String(source.source),
                reason:String(source.reason),
                count:Number(source.count)
            });
        }
        return {
            v:1,
            runId:String(_run.runId),
            stageName:String(_run.stageName),
            difficulty:String(_run.difficulty),
            outcome:String(_run.outcome),
            activeFrames:Number(_run.activeFrames),
            totalKills:Number(_run.totalKills),
            omittedKillTypes:Number(_run.omittedKillTypes),
            totalItemGains:Number(_run.totalItemGains),
            totalItemLosses:Number(_run.totalItemLosses),
            omittedItemFlowTypes:Number(_run.omittedItemFlowTypes),
            rewardRollOmissions:Number(_run.rewardRollOmissions),
            kills:kills,
            itemFlows:itemFlows
        };
    }

    private static function pushState():Void {
        if (_run == null) return;
        var server:Object = _root.server;
        if (server == undefined || server.isSocketConnected !== true
                || typeof server.sendTaskToNode != "function") return;
        var coins:Number = reviveCoinCount();
        var restricted:Boolean = _root.限制系统 != undefined
            && _root.限制系统.DisableResurrection == true;
        var reviveAllowed:Boolean = _run.life == "dead" && !_returnRequested
            && !restricted && coins > 0;
        var blocked:String = "";
        if (_run.life == "dead" && !_returnRequested && restricted) {
            blocked = "resurrection_restricted";
        } else if (_run.life == "dead" && !_returnRequested && coins <= 0) {
            blocked = "no_revive_coin";
        }
        try {
            server.sendTaskToNode("stage_outcome", {
                v:1,
                runId:String(_run.runId),
                revision:Number(_run.revision),
                stageName:String(_run.stageName),
                difficulty:String(_run.difficulty),
                outcome:String(_run.outcome),
                life:String(_run.life),
                activeFrames:Number(_run.activeFrames),
                reviveCoins:coins,
                reviveAllowed:reviveAllowed,
                reviveBlockedReason:blocked,
                canReturnBase:!_returnRequested
                    && (_run.life == "dead" || _run.outcome != "active"),
                settlement:String(_run.settlement),
                remainingRewards:Number(_run.remainingRewards)
            }, null);
        } catch (projectionError) {
            // C# 是可恢复投影；socket 竞态绝不能中断扣币、复活或结算终态。
            trace("[StageRunSession] stage outcome projection failed");
        }
    }

    private static function reviveCoinCount():Number {
        var count:Number = 0;
        try { count = Number(ItemUtil.getTotal("复活币")); } catch (countError) { count = 0; }
        if (isNaN(count) || count < 0) count = 0;
        return Math.floor(count);
    }

    private static function bumpRevision():Void {
        if (_run == null) return;
        var revision:Number = Number(_run.revision);
        if (isNaN(revision) || revision < 0) revision = 0;
        _run.revision = revision + 1;
    }

    private static function normalizeRewardName(name:String):String {
        if (name == "金钱") return "金币";
        if (name == "经验") return "经验值";
        return safeText(name, 128, "");
    }

    private static function isReportAssetKind(kind:String):Boolean {
        return kind == "money" || kind == "kpoint" || kind == "intel"
            || kind == "material" || kind == "item" || kind == "equip";
    }

    private static function safeAddCount(left:Number, right:Number):Number {
        var maximum:Number = 9007199254740991;
        if (!isWhole(left) || left < 0) left = 0;
        if (!isWhole(right) || right < 0) right = 0;
        return left > maximum - right ? maximum : left + right;
    }

    private static function copyDoll(value:Object):Object {
        if (value == null) return null;
        return {
            face:safeText(String(value.face), 128, ""),
            hair:safeText(String(value.hair), 128, ""),
            mask:safeText(String(value.mask), 128, ""),
            head:safeText(String(value.head), 128, ""),
            body:safeText(String(value.body), 128, ""),
            leg:safeText(String(value.leg), 128, ""),
            hand:safeText(String(value.hand), 128, ""),
            foot:safeText(String(value.foot), 128, ""),
            neck:safeText(String(value.neck), 128, ""),
            gender:safeText(String(value.gender), 128, "")
        };
    }

    private static function safeText(value:String, maxLength:Number, fallback:String):String {
        if (value == undefined || value == null || value == "undefined" || value == "null") {
            return fallback;
        }
        var result:String = "";
        for (var i:Number = 0; i < value.length && result.length < maxLength; i++) {
            var code:Number = value.charCodeAt(i);
            if (code >= 32 && code != 127) result += value.charAt(i);
        }
        return result.length == 0 ? fallback : result;
    }

    private static function safeWhole(value, minimum:Number, maximum:Number,
                                      fallback:Number):Number {
        var result:Number = Number(value);
        if (!isWhole(result) || result < minimum || result > maximum) return fallback;
        return result;
    }

    private static function isWhole(value):Boolean {
        return typeof value == "number" && (value - value) == 0
            && Math.floor(value) == value;
    }

    private static function isSafeToken(value:String, maxLength:Number):Boolean {
        if (value == undefined || value.length < 1 || value.length > maxLength) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            var valid:Boolean = (code >= 48 && code <= 57)
                || (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
                || code == 45 || code == 46 || code == 58 || code == 95;
            if (!valid) return false;
        }
        return true;
    }

    private static function hasOnlyKeys(value:Object, allowed:Array):Boolean {
        if (value == null || typeof value != "object" || value instanceof Array) return false;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function" && !value.hasOwnProperty(key)) continue;
            var found:Boolean = false;
            for (var i:Number = 0; i < allowed.length; i++) {
                if (key == allowed[i]) { found = true; break; }
            }
            if (!found) return false;
        }
        return true;
    }

    /** focused TestLoader 只读投影与隔离复位。 */
    public static function testOnlySnapshot():Object {
        if (_run == null) return null;
        return {
            runId:_run.runId,
            revision:_run.revision,
            outcome:_run.outcome,
            life:_run.life,
            activeFrames:_run.activeFrames,
            totalKills:_run.totalKills,
            settlement:_run.settlement,
            remainingRewards:_run.remainingRewards,
            report:_preparedReport,
            inventory:_preparedInventory,
            returnRequested:_returnRequested,
            settlementStarted:_settlementStarted,
            deliverAfterSettlement:_deliverAfterSettlement
        };
    }

    public static function testOnlyReset():Void {
        resetAuthorityForRestart();
    }

    /** 只供游戏整体 restart/dispose 调用；普通场景入口不得绕过生命周期门。 */
    public static function resetForRestart():Void {
        resetAuthorityForRestart();
    }

    private static function resetAuthorityForRestart():Void {
        _run = null;
        _processedIntents = {};
        _preparedInventory = null;
        _preparedReport = null;
        _settlementStarted = false;
        _returnRequested = false;
        _deliverAfterSettlement = false;
        _stageStartReservation = null;
        _testDeliverableResolver = null;
        _testDeliverableNavigator = null;
    }

    public static function testOnlySetDeliverableHooks(
            resolver:Function, navigator:Function):Void {
        _testDeliverableResolver = resolver;
        _testDeliverableNavigator = navigator;
    }
}
