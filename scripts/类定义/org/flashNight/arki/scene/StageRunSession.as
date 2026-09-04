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
    private static var SETTLEMENT_STORE_VERSION:Number = 1;
    private static var SETTLEMENT_RECORD_VERSION:Number = 1;
    private static var MAX_SETTLEMENT_RECEIPTS:Number = 128;
    private static var MAX_RECEIPT_FINGERPRINT_LENGTH:Number = 16384;
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
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
            settlementId:"",
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
        if (_preparedInventory != null || LootContainerService.hasStageSettlementPending()
                || hasPersistedSettlementPending()) {
            return "pending_stage_settlement";
        }
        if (_root.当前为战斗地图 === true) return "battle_map";
        return "";
    }

    /**
     * O1 临时只读观测面：把现役 scene wait 归一为固定 owner 名称。
     * 不触发 reservation、settlement、scene transition 或任何持久化。
     */
    public static function getObservationOwner():String {
        if (_stageStartReservation != null) return "stage_start_reservation";
        if (_run != null && !isRunTerminal()) {
            return _returnRequested ? "stage_settlement" : "stage_run";
        }
        if (_preparedInventory != null || _preparedReport != null
                || hasPersistedSettlementPending()) return "stage_settlement";
        if (_root.场景转换中 === true) return "scene_transition";
        if (_root.斗兽标定模式 === true) return "arena_calibration";
        if (_root.当前为战斗地图 === true) return "legacy_battle_map";
        return "base_scene";
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
        if (_preparedInventory != null || LootContainerService.hasStageSettlementPending()
                || hasPersistedSettlementPending()) {
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
        if (returned == null || returned.success !== true) {
            _deliverAfterSettlement = false;
            if (_preparedInventory != null && _preparedReport != null) {
                // 返回/淡出失败已撤销交付意图；若奖励此前已冻结，同步修正同一 pending，
                // 避免重启后把一次失败点击重新解释为自动导航。
                persistPreparedSettlement();
            }
        }
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
        // 奖励 manifest 已冻结并写入 _saveExt 后，仍必须确认整档真实落盘，
        // 才能让场景跳转/cleanup 开始。缺失函数、异常约定值和 false 均 fail-closed；
        // 失败时保留同一 prepared/pending，下一次请求只重试持久化与 flush，绝不重 roll。
        if (_root.存档系统 == null || typeof _root.存档系统.flushBeforeTransition != "function") return false;
        var durable:Boolean = false;
        try {
            durable = (_root.存档系统.flushBeforeTransition("stage.return_base") === true);
        } catch (flushError) {
            durable = false;
        }
        if (!durable) return false;
        _returnRequested = true;
        bumpRevision();
        pushState();
        return true;
    }

    public static function prepareSettlement():Boolean {
        if (_preparedInventory != null && _preparedReport != null) {
            return persistPreparedSettlement().success === true;
        }
        if (_run == null) return false;
        // 任意无法解释的持久化结算都必须先恢复/修复，绝不能重新 roll 后覆盖。
        if (hasPersistedSettlementPending()) return false;
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
        var persisted:Object = persistPreparedSettlement();
        if (persisted == null || persisted.success !== true) return false;
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
        if ((settlement == "claimed" || settlement == "abandoned" || settlement == "error")
                && _run.settlementId != undefined && String(_run.settlementId) != "") {
            // Loot 正常路径会先携 exact receipt 清理并 flush；本调用于是幂等命中 marker。
            // 旧/本地调用若尚未清理，也至少在释放内存 authority 前写 terminal marker。
            var cleared:Object = clearPersistedSettlement(
                String(_run.settlementId), settlement, null);
            if (cleared == null || cleared.success !== true) {
                trace("[StageRunSession] persisted settlement terminal cleanup failed");
                return;
            }
        }
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
     * 把已经 materialize 的同一份奖励写进存档扩展域。这里只写 _saveExt 并标脏；
     * 是否真正 durable 必须由调用方随后以 SaveManager.flushNow()==true 证明。
     */
    public static function persistPreparedSettlement():Object {
        if (_run == null || _preparedInventory == null || _preparedReport == null) {
            return settlementFailure("settlement_not_prepared");
        }
        var serialized:Object = serializeSettlementInventory(_preparedInventory);
        if (serialized == null || serialized.success !== true) {
            return settlementFailure("invalid_prepared_inventory");
        }
        var report:Object = normalizePersistedReport(_preparedReport);
        if (report == null) return settlementFailure("invalid_prepared_report");

        var inspected:Object = inspectSettlementStore();
        if (inspected.success !== true) return inspected;
        var store:Object = inspected.store;
        if (store == null) store = {v:SETTLEMENT_STORE_VERSION, nextSeq:1};
        var existing:Object = store.pending;
        if (existing !== undefined && existing !== null) {
            var decoded:Object = decodePendingSettlement(existing);
            if (decoded == null) return settlementFailure("malformed_persisted_settlement");
            if (String(existing.runId) !== String(_run.runId)
                    || !sameManifest(existing.manifest, serialized.manifest)
                    || !samePlainValue(existing.report, report, 0)) {
                return settlementFailure("pending_settlement_conflict");
            }
            if (_run.settlementId != undefined && String(_run.settlementId) != ""
                    && String(_run.settlementId) !== String(existing.settlementId)) {
                return settlementFailure("pending_settlement_conflict");
            }
            _run.settlementId = String(existing.settlementId);
            if (existing.deliverAfterSettlement !== (_deliverAfterSettlement === true)) {
                var updated:Object = clonePlainValue(existing, 0);
                updated.deliverAfterSettlement = _deliverAfterSettlement === true;
                var replacementStore:Object = cloneStoreWithPending(store, updated);
                var updatedWrite:Object = writeSettlementStore(replacementStore);
                if (updatedWrite.success !== true) return updatedWrite;
            }
            return {
                success:true, error:"", duplicate:true,
                settlementId:String(existing.settlementId)
            };
        }

        var nextSeq:Number = Number(store.nextSeq);
        if (!isWhole(nextSeq) || nextSeq < 1 || nextSeq >= MAX_SAFE_INTEGER) {
            return settlementFailure("settlement_sequence_exhausted");
        }
        var settlementId:String = "stage.settlement." + nextSeq;
        var pending:Object = {
            v:SETTLEMENT_RECORD_VERSION,
            settlementId:settlementId,
            runId:String(_run.runId),
            runRevision:Number(_run.revision),
            state:"prepared",
            outcome:String(_run.outcome),
            life:String(_run.life),
            capacity:Number(serialized.capacity),
            report:report,
            manifest:serialized.manifest,
            remainingManifest:clonePlainValue(serialized.manifest, 0),
            remainingCount:Number(serialized.manifest.length),
            receipts:[],
            deliverAfterSettlement:_deliverAfterSettlement === true
        };
        var replacement:Object = {
            v:SETTLEMENT_STORE_VERSION,
            nextSeq:nextSeq + 1,
            pending:pending
        };
        if (store.lastTerminal !== undefined && store.lastTerminal !== null) {
            replacement.lastTerminal = clonePlainValue(store.lastTerminal, 0);
        }
        var written:Object = writeSettlementStore(replacement);
        if (written.success !== true) return written;
        _run.settlementId = settlementId;
        return {success:true, error:"", duplicate:false, settlementId:settlementId};
    }

    /**
     * 每次领取资产提交后，把权威 remaining inventory 与 operation receipt 一并写入 ext。
     * 同 operationId + 同结果是幂等成功；同 id 不同结果 fail closed。
     */
    public static function recordSettlementProgress(settlementId:String,
            operationId:String, remainingInventory:ArrayInventory, receipt:Object):Object {
        if (!isSafeToken(String(settlementId), 96)
                || !isSafeToken(String(operationId), 96)
                || remainingInventory == null) {
            return settlementFailure("invalid_settlement_progress");
        }
        var inspected:Object = inspectSettlementStore();
        if (inspected.success !== true) return inspected;
        var store:Object = inspected.store;
        if (store == null || store.pending === undefined || store.pending === null) {
            return settlementFailure("no_pending_settlement");
        }
        var decoded:Object = decodePendingSettlement(store.pending);
        if (decoded == null) return settlementFailure("malformed_persisted_settlement");
        if (String(store.pending.settlementId) !== String(settlementId)) {
            return settlementFailure("settlement_id_mismatch");
        }

        var serialized:Object = serializeSettlementInventory(remainingInventory);
        if (serialized == null || serialized.success !== true
                || Number(serialized.capacity) != Number(store.pending.capacity)
                || !isManifestSubset(serialized.manifest, store.pending.manifest)) {
            return settlementFailure("invalid_remaining_inventory");
        }
        var normalizedReceipt:Object = normalizeProgressReceipt(
            operationId, receipt, Number(serialized.manifest.length));
        if (normalizedReceipt == null) return settlementFailure("invalid_claim_receipt");

        var receipts:Array = store.pending.receipts;
        for (var i:Number = 0; i < receipts.length; i++) {
            if (String(receipts[i].operationId) !== String(operationId)) continue;
            if (!samePlainValue(receipts[i], normalizedReceipt, 0)
                    || !sameManifest(store.pending.remainingManifest,
                        serialized.manifest)) {
                return settlementFailure("operation_conflict");
            }
            return {
                success:true, error:"", duplicate:true,
                settlementId:String(settlementId), remainingCount:serialized.manifest.length
            };
        }
        var appliedCount:Number = normalizedReceipt.kind == "claim"
            ? 1 : Number(normalizedReceipt.appliedCount);
        if (!isWhole(appliedCount) || appliedCount < 1
                || appliedCount > MAX_REWARD_SLOTS
                || !isManifestSubset(serialized.manifest, decoded.remainingManifest)
                || Number(serialized.manifest.length)
                    != Number(decoded.remainingManifest.length) - appliedCount) {
            return settlementFailure("invalid_remaining_inventory");
        }
        if (receipts.length >= MAX_SETTLEMENT_RECEIPTS) {
            return settlementFailure("settlement_receipt_capacity");
        }

        var pending:Object = clonePlainValue(store.pending, 0);
        pending.remainingManifest = serialized.manifest;
        pending.remainingCount = Number(serialized.manifest.length);
        pending.receipts.push(normalizedReceipt);
        if (_run != null && String(_run.settlementId) === String(settlementId)
                && (_run.settlement == "prepared" || _run.settlement == "web_active"
                    || _run.settlement == "rewards_pending")) {
            pending.state = String(_run.settlement);
        }
        var replacement:Object = cloneStoreWithPending(store, pending);
        var written:Object = writeSettlementStore(replacement);
        if (written.success !== true) return written;
        if (_run != null && String(_run.settlementId) === String(settlementId)) {
            _preparedInventory = remainingInventory;
            _run.remainingRewards = Number(serialized.manifest.length);
        }
        return {
            success:true, error:"", duplicate:false,
            settlementId:String(settlementId), remainingCount:serialized.manifest.length
        };
    }

    /** 返回 ext 中某个领取操作的持久化幂等 receipt；不泄露可变存档引用。 */
    public static function getPersistedSettlementReceipt(
            settlementId:String, operationId:String):Object {
        var inspected:Object = inspectSettlementStore();
        if (inspected.success !== true) return inspected;
        var store:Object = inspected.store;
        if (store == null || store.pending === undefined || store.pending === null) {
            return settlementFailure("no_pending_settlement");
        }
        if (decodePendingSettlement(store.pending) == null) {
            return settlementFailure("malformed_persisted_settlement");
        }
        if (String(store.pending.settlementId) !== String(settlementId)
                || !isSafeToken(String(operationId), 96)) {
            return settlementFailure("settlement_id_mismatch");
        }
        var receipts:Array = store.pending.receipts;
        for (var i:Number = 0; i < receipts.length; i++) {
            if (String(receipts[i].operationId) === String(operationId)) {
                return {success:true, error:"", found:true,
                    receipt:clonePlainValue(receipts[i], 0)};
            }
        }
        return {success:true, error:"", found:false, receipt:null};
    }

    /** 重启后的 Loot authority 可一次读取全部有界 receipts 来重建幂等 journal。 */
    public static function getPersistedSettlementReceipts(settlementId:String):Object {
        var inspected:Object = inspectSettlementStore();
        if (inspected.success !== true) return inspected;
        var store:Object = inspected.store;
        if (store == null || store.pending === undefined || store.pending === null) {
            return settlementFailure("no_pending_settlement");
        }
        var decoded:Object = decodePendingSettlement(store.pending);
        if (decoded == null) return settlementFailure("malformed_persisted_settlement");
        if (String(store.pending.settlementId) !== String(settlementId)) {
            return settlementFailure("settlement_id_mismatch");
        }
        return {success:true, error:"",
            originalCount:Number(decoded.manifest.length),
            remainingCount:Number(decoded.remainingManifest.length),
            receipts:clonePlainValue(decoded.receipts, 0)};
    }

    /**
     * 终态只清 pending 并保留一个有界 terminal marker；仍不自行 flush。
     * 这让资产写与 pending 清理由 SaveManager 的同一次 durable commit 覆盖。
     */
    public static function clearPersistedSettlement(settlementId:String,
            terminalState:String, receipt:Object):Object {
        if (!isSafeToken(String(settlementId), 96)
                || (terminalState != "claimed" && terminalState != "abandoned"
                    && terminalState != "error")) {
            return settlementFailure("invalid_terminal_settlement");
        }
        var inspected:Object = inspectSettlementStore();
        if (inspected.success !== true) return inspected;
        var store:Object = inspected.store;
        if (store == null) return settlementFailure("no_pending_settlement");
        if (store.pending === undefined || store.pending === null) {
            var prior:Object = store.lastTerminal;
            if (prior != null && String(prior.settlementId) === String(settlementId)
                    && String(prior.terminalState) === String(terminalState)) {
                return {success:true, error:"", duplicate:true,
                    settlementId:String(settlementId)};
            }
            return settlementFailure("no_pending_settlement");
        }
        if (decodePendingSettlement(store.pending) == null) {
            return settlementFailure("malformed_persisted_settlement");
        }
        if (String(store.pending.settlementId) !== String(settlementId)) {
            return settlementFailure("settlement_id_mismatch");
        }
        var terminalReceipt:Object = normalizeTerminalReceipt(receipt, terminalState);
        if (terminalReceipt == null) return settlementFailure("invalid_terminal_receipt");
        var marker:Object = {
            v:1,
            settlementId:String(settlementId),
            terminalState:String(terminalState),
            receipt:terminalReceipt
        };
        var replacement:Object = {
            v:SETTLEMENT_STORE_VERSION,
            nextSeq:Number(store.nextSeq),
            lastTerminal:marker
        };
        var written:Object = writeSettlementStore(replacement);
        if (written.success !== true) return written;
        return {success:true, error:"", duplicate:false,
            settlementId:String(settlementId)};
    }

    /**
     * SaveManager 完成 ext 读入后调用。它从 remainingManifest 重建真实 BaseItem/
     * ArrayInventory，并把进程态 Web authority 规范化为可恢复的 rewards_pending。
     */
    public static function restorePendingSettlement():Object {
        var inspected:Object = inspectSettlementStore();
        if (inspected.success !== true) return inspected;
        var store:Object = inspected.store;
        if (store == null || store.pending === undefined || store.pending === null) {
            return {success:true, error:"", restored:false};
        }
        var decoded:Object = decodePendingSettlement(store.pending);
        if (decoded == null) return settlementFailure("malformed_persisted_settlement");
        if (_run != null || _preparedInventory != null || _preparedReport != null) {
            if (_run != null
                    && String(_run.settlementId) === String(store.pending.settlementId)
                    && _preparedInventory != null && _preparedReport != null) {
                return {success:true, error:"", restored:false, duplicate:true,
                    settlementId:String(store.pending.settlementId)};
            }
            return settlementFailure("settlement_authority_busy");
        }

        var report:Object = decoded.report;
        var revision:Number = Number(store.pending.runRevision);
        if (revision >= MAX_SAFE_INTEGER) revision = MAX_SAFE_INTEGER - 1;
        _run = {
            v:1,
            runId:String(store.pending.runId),
            revision:revision + 1,
            stageName:String(report.stageName),
            difficulty:String(report.difficulty),
            outcome:String(store.pending.outcome),
            life:String(store.pending.life),
            activeFrames:Number(report.activeFrames),
            totalKills:Number(report.totalKills),
            kills:clonePlainValue(report.kills, 0),
            killsByKey:{},
            omittedKillTypes:Number(report.omittedKillTypes),
            omittedKillKeys:{},
            totalItemGains:Number(report.totalItemGains),
            totalItemLosses:Number(report.totalItemLosses),
            itemFlows:clonePlainValue(report.itemFlows, 0),
            itemFlowsByKey:{},
            omittedItemFlowTypes:Number(report.omittedItemFlowTypes),
            omittedItemFlowKeys:{},
            rewardRollOmissions:Number(report.rewardRollOmissions),
            settlement:"rewards_pending",
            settlementId:String(store.pending.settlementId),
            remainingRewards:Number(store.pending.remainingCount)
        };
        _processedIntents = {};
        _preparedInventory = decoded.remainingInventory;
        _preparedReport = report;
        _settlementStarted = false;
        _returnRequested = true;
        _deliverAfterSettlement = store.pending.deliverAfterSettlement === true;
        _stageStartReservation = null;
        pushState();
        return {
            success:true, error:"", restored:true,
            settlementId:String(store.pending.settlementId),
            remainingCount:Number(store.pending.remainingCount),
            receiptCount:Number(store.pending.receipts.length)
        };
    }

    /** 降级/畸形 store 也算未知 pending，保证旧构建不会覆盖未来权威。 */
    public static function hasPersistedSettlementPending():Boolean {
        var ext:Object = _root._saveExt;
        if (ext === undefined || ext === null) return false;
        if (typeof ext != "object" || ext instanceof Array) return true;
        if (ext.stageSettlement === undefined || ext.stageSettlement === null) return false;
        var inspected:Object = inspectSettlementStore();
        if (inspected.success !== true) return true;
        return inspected.store != null && inspected.store.pending !== undefined
            && inspected.store.pending !== null;
    }

    /** Loot authority 建立/恢复时读取当前稳定 identity；空串表示无可绑定结算。 */
    public static function getCurrentSettlementId():String {
        if (_run == null || _run.settlementId == undefined) return "";
        var settlementId:String = String(_run.settlementId);
        return isSafeToken(settlementId, 96) ? settlementId : "";
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
            // 情报持有上限分流（与地图箱物化/敌人掉落同一语义）：掷骰照旧，生成量按
            // maxvalue 截断；已达上限的零价剧情情报不生成，避免结算箱出现永恒受阻格。
            var informationPlan:Object = ItemUtil.planInformationAcquire(name, quantity);
            if (informationPlan.valid === true) {
                if (Number(informationPlan.accepted) <= 0) {
                    omissions++;
                    continue;
                }
                quantity = Number(informationPlan.accepted);
            }
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

    private static function settlementFailure(errorCode:String):Object {
        return {success:false, error:errorCode};
    }

    private static function inspectSettlementStore():Object {
        var ext:Object = _root._saveExt;
        if (ext === undefined || ext === null) {
            return {success:true, error:"", store:null};
        }
        if (typeof ext != "object" || ext instanceof Array) {
            return settlementFailure("malformed_save_ext");
        }
        var raw:Object = ext.stageSettlement;
        if (raw === undefined || raw === null) {
            return {success:true, error:"", store:null};
        }
        if (typeof raw != "object" || raw instanceof Array
                || typeof raw.v != "number" || !isWhole(Number(raw.v))) {
            return settlementFailure("malformed_settlement_store");
        }
        if (Number(raw.v) > SETTLEMENT_STORE_VERSION) {
            return settlementFailure("future_settlement_store_version");
        }
        if (Number(raw.v) != SETTLEMENT_STORE_VERSION
                || !hasOnlyKeys(raw, ["v", "nextSeq", "pending", "lastTerminal"])
                || !isWhole(Number(raw.nextSeq)) || Number(raw.nextSeq) < 1
                || Number(raw.nextSeq) > MAX_SAFE_INTEGER) {
            return settlementFailure("malformed_settlement_store");
        }
        if (raw.pending !== undefined && raw.pending !== null
                && (typeof raw.pending != "object" || raw.pending instanceof Array)) {
            return settlementFailure("malformed_settlement_store");
        }
        if (raw.lastTerminal !== undefined && raw.lastTerminal !== null
                && normalizeTerminalMarker(raw.lastTerminal) == null) {
            return settlementFailure("malformed_settlement_store");
        }
        return {success:true, error:"", store:raw};
    }

    private static function writeSettlementStore(store:Object):Object {
        if (store == null || inspectReplacementStore(store) !== true) {
            return settlementFailure("invalid_settlement_store_write");
        }
        var ext:Object = _root._saveExt;
        if (ext === undefined || ext === null) {
            ext = {};
            _root._saveExt = ext;
        } else if (typeof ext != "object" || ext instanceof Array) {
            return settlementFailure("malformed_save_ext");
        }
        ext.stageSettlement = store;
        if (_root.存档系统 != undefined && _root.存档系统 != null) {
            _root.存档系统.dirtyMark = true;
            if (typeof _root.存档系统.markDirty == "function") {
                _root.存档系统.markDirty();
            }
        }
        return {success:true, error:""};
    }

    private static function inspectReplacementStore(store:Object):Boolean {
        if (store == null || typeof store != "object" || store instanceof Array
                || Number(store.v) != SETTLEMENT_STORE_VERSION
                || !isWhole(Number(store.nextSeq)) || Number(store.nextSeq) < 1
                || Number(store.nextSeq) > MAX_SAFE_INTEGER) return false;
        if (store.pending !== undefined && store.pending !== null
                && decodePendingSettlement(store.pending) == null) return false;
        if (store.lastTerminal !== undefined && store.lastTerminal !== null
                && normalizeTerminalMarker(store.lastTerminal) == null) return false;
        return true;
    }

    private static function cloneStoreWithPending(store:Object, pending:Object):Object {
        var result:Object = {
            v:SETTLEMENT_STORE_VERSION,
            nextSeq:Number(store.nextSeq),
            pending:pending
        };
        if (store.lastTerminal !== undefined && store.lastTerminal !== null) {
            result.lastTerminal = clonePlainValue(store.lastTerminal, 0);
        }
        return result;
    }

    private static function serializeSettlementInventory(inventory:ArrayInventory):Object {
        if (inventory == null || !isWhole(Number(inventory.capacity))
                || Number(inventory.capacity) < 8
                || Number(inventory.capacity) > MAX_REWARD_SLOTS
                || Number(inventory.capacity) % REWARD_COLUMNS != 0) return null;
        var indexes:Array = inventory.getIndexes();
        if (!(indexes instanceof Array) || indexes.length > MAX_REWARD_SLOTS) return null;
        var manifest:Array = [];
        var previous:Number = -1;
        for (var i:Number = 0; i < indexes.length; i++) {
            var slot:Number = Number(indexes[i]);
            if (!isWhole(slot) || slot <= previous || slot < 0
                    || slot >= Number(inventory.capacity)) return null;
            var item:Object = normalizePersistedItem(inventory.getItem(String(slot)));
            if (item == null) return null;
            manifest.push({slot:slot, item:item});
            previous = slot;
        }
        return {success:true, capacity:Number(inventory.capacity), manifest:manifest};
    }

    private static function decodePendingSettlement(raw:Object):Object {
        if (raw == null || typeof raw != "object" || raw instanceof Array
                || !hasOnlyKeys(raw, ["v", "settlementId", "runId", "runRevision",
                    "state", "outcome", "life", "capacity", "report", "manifest",
                    "remainingManifest", "remainingCount", "receipts",
                    "deliverAfterSettlement"])
                || Number(raw.v) != SETTLEMENT_RECORD_VERSION
                || !isSafeToken(String(raw.settlementId), 96)
                || !isSafeToken(String(raw.runId), 96)
                || !isWhole(Number(raw.runRevision)) || Number(raw.runRevision) < 1
                || Number(raw.runRevision) > MAX_SAFE_INTEGER
                || (raw.state != "prepared" && raw.state != "web_active"
                    && raw.state != "rewards_pending")
                || (raw.outcome != "victory" && raw.outcome != "failure"
                    && raw.outcome != "retreat")
                || (raw.life != "alive" && raw.life != "dead" && raw.life != "reviving")
                || !isWhole(Number(raw.capacity)) || Number(raw.capacity) < 8
                || Number(raw.capacity) > MAX_REWARD_SLOTS
                || Number(raw.capacity) % REWARD_COLUMNS != 0
                || typeof raw.deliverAfterSettlement != "boolean") return null;
        var report:Object = normalizePersistedReport(raw.report);
        if (report == null || String(report.runId) !== String(raw.runId)
                || String(report.outcome) !== String(raw.outcome)) return null;
        var original:Object = decodeManifest(raw.manifest, Number(raw.capacity));
        var remaining:Object = decodeManifest(raw.remainingManifest, Number(raw.capacity));
        if (original == null || remaining == null
                || !isManifestSubset(remaining.manifest, original.manifest)
                || !isWhole(Number(raw.remainingCount))
                || Number(raw.remainingCount) != remaining.manifest.length) return null;
        if (!(raw.receipts instanceof Array)
                || raw.receipts.length > MAX_SETTLEMENT_RECEIPTS) return null;
        var seen:Object = {};
        var receipts:Array = [];
        var previousRevision:Number = 1;
        var previousRemaining:Number = Number(original.manifest.length);
        for (var i:Number = 0; i < raw.receipts.length; i++) {
            var receipt:Object = normalizeStoredProgressReceipt(raw.receipts[i]);
            if (receipt == null) return null;
            var operationKey:String = "$" + String(receipt.operationId);
            if (seen[operationKey] === true) return null;
            var appliedCount:Number = receipt.kind == "claim"
                ? 1 : Number(receipt.appliedCount);
            if (!isWhole(appliedCount) || appliedCount < 1
                    || appliedCount > MAX_REWARD_SLOTS
                    || Number(receipt.authorityRevision)
                        < previousRevision + appliedCount
                    || Number(receipt.remainingCount)
                        != previousRemaining - appliedCount) return null;
            seen[operationKey] = true;
            receipts.push(receipt);
            previousRevision = Number(receipt.authorityRevision);
            previousRemaining = Number(receipt.remainingCount);
        }
        if (previousRemaining != Number(remaining.manifest.length)) return null;
        return {
            report:report,
            manifest:original.manifest,
            remainingManifest:remaining.manifest,
            remainingInventory:remaining.inventory,
            receipts:receipts
        };
    }

    private static function decodeManifest(raw:Object, capacity:Number):Object {
        if (!(raw instanceof Array) || raw.length > MAX_REWARD_SLOTS) return null;
        var manifest:Array = [];
        var inventory:ArrayInventory = new ArrayInventory(null, capacity);
        var previous:Number = -1;
        for (var i:Number = 0; i < raw.length; i++) {
            var row:Object = raw[i];
            if (row == null || !hasOnlyKeys(row, ["slot", "item"])) return null;
            var slot:Number = Number(row.slot);
            if (!isWhole(slot) || slot <= previous || slot < 0 || slot >= capacity) return null;
            var itemData:Object = normalizePersistedItem(row.item);
            if (itemData == null) return null;
            var item:BaseItem = BaseItem.createFromObject(clonePlainValue(itemData, 0));
            if (item == null || !inventory.add(slot, item)) return null;
            manifest.push({slot:slot, item:itemData});
            previous = slot;
        }
        return {manifest:manifest, inventory:inventory};
    }

    private static function normalizePersistedItem(raw:Object):Object {
        if (raw == null || typeof raw != "object" || raw instanceof Array
                || !hasOnlyKeys(raw, ["name", "value", "lastUpdate"])
                || typeof raw.name != "string"
                || !isBoundedText(String(raw.name), 128, false)
                || !ItemUtil.isItem(String(raw.name))
                || typeof raw.lastUpdate != "number"
                || !isWhole(Number(raw.lastUpdate)) || Number(raw.lastUpdate) < 0
                || Number(raw.lastUpdate) > MAX_SAFE_INTEGER) return null;
        var value:Object;
        if (ItemUtil.isEquipment(String(raw.name))) {
            if (raw.value == null || typeof raw.value != "object"
                    || raw.value instanceof Array) return null;
            var cloned:Object = cloneSaveValue(raw.value, 0);
            if (cloned == null || cloned.success !== true) return null;
            value = cloned.value;
        } else {
            if (typeof raw.value != "number" || !isWhole(Number(raw.value))
                    || Number(raw.value) <= 0 || Number(raw.value) > MAX_SAFE_INTEGER) return null;
            value = Number(raw.value);
        }
        return {name:String(raw.name), value:value, lastUpdate:Number(raw.lastUpdate)};
    }

    private static function normalizePersistedReport(raw:Object):Object {
        if (raw == null || typeof raw != "object" || raw instanceof Array
                || !hasOnlyKeys(raw, ["v", "runId", "stageName", "difficulty", "outcome",
                    "activeFrames", "totalKills", "omittedKillTypes", "totalItemGains",
                    "totalItemLosses", "omittedItemFlowTypes", "rewardRollOmissions",
                    "kills", "itemFlows"])
                || Number(raw.v) != 1 || typeof raw.runId != "string"
                || typeof raw.stageName != "string" || typeof raw.difficulty != "string"
                || typeof raw.outcome != "string" || !isSafeToken(String(raw.runId), 96)
                || !isBoundedText(String(raw.stageName), 96, false)
                || !isBoundedText(String(raw.difficulty), 48, false)
                || (raw.outcome != "victory" && raw.outcome != "failure"
                    && raw.outcome != "retreat")
                || !isCount(raw.activeFrames) || !isCount(raw.totalKills)
                || !isCount(raw.omittedKillTypes) || !isCount(raw.totalItemGains)
                || !isCount(raw.totalItemLosses) || !isCount(raw.omittedItemFlowTypes)
                || !isCount(raw.rewardRollOmissions)
                || !(raw.kills instanceof Array) || raw.kills.length > MAX_KILL_TYPES
                || !(raw.itemFlows instanceof Array)
                || raw.itemFlows.length > MAX_ITEM_FLOW_TYPES) return null;
        var kills:Array = [];
        for (var i:Number = 0; i < raw.kills.length; i++) {
            var kill:Object = normalizePersistedKill(raw.kills[i]);
            if (kill == null) return null;
            kills.push(kill);
        }
        var flows:Array = [];
        for (i = 0; i < raw.itemFlows.length; i++) {
            var flow:Object = normalizePersistedFlow(raw.itemFlows[i]);
            if (flow == null) return null;
            flows.push(flow);
        }
        return {
            v:1,
            runId:String(raw.runId),
            stageName:String(raw.stageName),
            difficulty:String(raw.difficulty),
            outcome:String(raw.outcome),
            activeFrames:Number(raw.activeFrames),
            totalKills:Number(raw.totalKills),
            omittedKillTypes:Number(raw.omittedKillTypes),
            totalItemGains:Number(raw.totalItemGains),
            totalItemLosses:Number(raw.totalItemLosses),
            omittedItemFlowTypes:Number(raw.omittedItemFlowTypes),
            rewardRollOmissions:Number(raw.rewardRollOmissions),
            kills:kills,
            itemFlows:flows
        };
    }

    private static function normalizePersistedKill(raw:Object):Object {
        if (raw == null || typeof raw != "object" || raw instanceof Array
                || !hasOnlyKeys(raw,
                ["key", "displayName", "iconName", "doll", "eliteLevel", "count"])
                || typeof raw.key != "string" || typeof raw.displayName != "string"
                || typeof raw.iconName != "string"
                || !isBoundedText(String(raw.key), 128, false)
                || !isBoundedText(String(raw.displayName), 96, false)
                || !isBoundedText(String(raw.iconName), 128, true)
                || !isWhole(Number(raw.eliteLevel)) || Number(raw.eliteLevel) < 0
                || Number(raw.eliteLevel) > 16 || !isCount(raw.count)
                || Number(raw.count) < 1) return null;
        var doll:Object = normalizePersistedDoll(raw.doll);
        if (raw.doll != null && doll == null) return null;
        return {key:String(raw.key), displayName:String(raw.displayName),
            iconName:String(raw.iconName), doll:doll,
            eliteLevel:Number(raw.eliteLevel), count:Number(raw.count)};
    }

    private static function normalizePersistedDoll(raw:Object):Object {
        if (raw === undefined || raw === null) return null;
        var keys:Array = ["face", "hair", "mask", "head", "body", "leg",
            "hand", "foot", "neck", "gender"];
        if (!hasOnlyKeys(raw, keys)) return null;
        var result:Object = {};
        for (var i:Number = 0; i < keys.length; i++) {
            var key:String = String(keys[i]);
            if (typeof raw[key] != "string") return null;
            if (!isBoundedText(String(raw[key]), 128, true)) return null;
            result[key] = String(raw[key]);
        }
        return result;
    }

    private static function normalizePersistedFlow(raw:Object):Object {
        if (raw == null || typeof raw != "object" || raw instanceof Array
                || !hasOnlyKeys(raw, ["direction", "kind", "itemKey",
                "displayName", "iconName", "tier", "source", "reason", "count"])
                || typeof raw.direction != "string" || typeof raw.kind != "string"
                || typeof raw.itemKey != "string" || typeof raw.displayName != "string"
                || typeof raw.iconName != "string" || typeof raw.tier != "string"
                || typeof raw.source != "string" || typeof raw.reason != "string"
                || (raw.direction != "gain" && raw.direction != "loss")
                || !isReportAssetKind(String(raw.kind))
                || !isBoundedText(String(raw.itemKey), 128, false)
                || !isBoundedText(String(raw.displayName), 96, false)
                || !isBoundedText(String(raw.iconName), 128, true)
                || !isBoundedText(String(raw.tier), 48, true)
                || !isBoundedText(String(raw.source), 48, false)
                || !isBoundedText(String(raw.reason), 64, true)
                || !isCount(raw.count) || Number(raw.count) < 1) return null;
        return {direction:String(raw.direction), kind:String(raw.kind),
            itemKey:String(raw.itemKey), displayName:String(raw.displayName),
            iconName:String(raw.iconName), tier:String(raw.tier),
            source:String(raw.source), reason:String(raw.reason), count:Number(raw.count)};
    }

    /**
     * SOL migrate 与 Protocol 2 _applyCore 共用的纯数据 normalizer。
     * AMF0/JSON 存档往返无法保留空数组：pending 的 manifest/remainingManifest/
     * receipts 与 report 的 kills/itemFlows 为空时会以空对象 {} 落盘，读回后被
     * decodePendingSettlement / normalizePersistedReport 误判为
     * malformed_persisted_settlement；hasPersistedSettlementPending 对畸形
     * store 恒 true，新关卡永久拒入、场景退出被拒（软锁）。这里只把“空对象”
     * 修复为 []；带键的非数组仍是真实损坏，继续交给 decode 侧 fail closed。
     * 字段集与 launcher C# SaveMigrator.NormalizeStageSettlementEmptyArrays 对齐。
     */
    public static function normalizeSaveData(mydata:Object):Object {
        if (mydata == null) return {ok:true, changed:false};
        var ext:Object = mydata.ext;
        if (ext == null || typeof ext != "object" || ext instanceof Array) {
            return {ok:true, changed:false};
        }
        var store:Object = ext.stageSettlement;
        if (store == null || typeof store != "object" || store instanceof Array
                || Number(store.v) != SETTLEMENT_STORE_VERSION) {
            return {ok:true, changed:false};
        }
        var pending:Object = store.pending;
        if (pending == null || typeof pending != "object" || pending instanceof Array
                || Number(pending.v) != SETTLEMENT_RECORD_VERSION) {
            return {ok:true, changed:false};
        }
        var changed:Boolean = false;
        if (normalizeEmptyArrayField(pending, "manifest")) changed = true;
        if (normalizeEmptyArrayField(pending, "remainingManifest")) changed = true;
        if (normalizeEmptyArrayField(pending, "receipts")) changed = true;
        var report:Object = pending.report;
        if (report != null && typeof report == "object" && !(report instanceof Array)
                && Number(report.v) == 1) {
            if (normalizeEmptyArrayField(report, "kills")) changed = true;
            if (normalizeEmptyArrayField(report, "itemFlows")) changed = true;
        }
        return {ok:true, changed:changed};
    }

    private static function normalizeEmptyArrayField(owner:Object, key:String):Boolean {
        var value:Object = owner[key];
        if (value != null && typeof value == "object" && !(value instanceof Array)
                && emptyOwnObject(value)) {
            owner[key] = [];
            return true;
        }
        return false;
    }

    private static function emptyOwnObject(value:Object):Boolean {
        for (var key:String in value) return false;
        return true;
    }

    private static function normalizeProgressReceipt(operationId:String,
            raw:Object, remainingCount:Number):Object {
        if (raw == null || typeof raw != "object" || raw instanceof Array
                || !hasOnlyKeys(raw, ["kind", "fingerprint", "authorityRevision",
                    "appliedCount", "resultState", "error"])) return null;
        if (typeof raw.kind != "string" || typeof raw.fingerprint != "string") return null;
        var kind:String = String(raw.kind);
        if (kind != "claim" && kind != "claim_batch") return null;
        if (!isBoundedText(String(raw.fingerprint), MAX_RECEIPT_FINGERPRINT_LENGTH, false)
                || !isCount(raw.authorityRevision)) return null;
        if (kind == "claim_batch" && raw.appliedCount === undefined) return null;
        var result:Object = {
            operationId:String(operationId),
            kind:kind,
            fingerprint:String(raw.fingerprint),
            authorityRevision:Number(raw.authorityRevision),
            remainingCount:Number(remainingCount)
        };
        if (raw.appliedCount !== undefined) {
            if (!isWhole(Number(raw.appliedCount)) || Number(raw.appliedCount) < 1
                    || Number(raw.appliedCount) > MAX_REWARD_SLOTS
                    || (kind == "claim" && Number(raw.appliedCount) != 1)) return null;
            result.appliedCount = Number(raw.appliedCount);
        }
        if (raw.resultState !== undefined) {
            if (!isBoundedText(String(raw.resultState), 48, false)) return null;
            result.resultState = String(raw.resultState);
        }
        if (raw.error !== undefined) {
            if (!isBoundedText(String(raw.error), 96, true)) return null;
            result.error = String(raw.error);
        }
        return result;
    }

    private static function normalizeStoredProgressReceipt(raw:Object):Object {
        if (raw == null || typeof raw != "object" || raw instanceof Array
                || !isSafeToken(String(raw.operationId), 96)
                || !isCount(raw.remainingCount)) return null;
        var source:Object = {
            kind:raw.kind,
            fingerprint:raw.fingerprint,
            authorityRevision:raw.authorityRevision
        };
        if (raw.appliedCount !== undefined) source.appliedCount = raw.appliedCount;
        if (raw.resultState !== undefined) source.resultState = raw.resultState;
        if (raw.error !== undefined) source.error = raw.error;
        var normalized:Object = normalizeProgressReceipt(
            String(raw.operationId), source, Number(raw.remainingCount));
        if (normalized == null || !samePlainValue(raw, normalized, 0)) return null;
        return normalized;
    }

    private static function normalizeTerminalReceipt(raw:Object, terminalState:String):Object {
        if (raw === undefined || raw === null) {
            return {operationId:"", kind:"terminal", terminalState:terminalState};
        }
        if (typeof raw != "object" || raw instanceof Array
                || !hasOnlyKeys(raw, ["operationId", "kind", "fingerprint",
                    "authorityRevision", "appliedCount", "error", "terminalState"])) return null;
        if (raw.terminalState !== undefined
                && String(raw.terminalState) !== String(terminalState)) return null;
        var operationId:String = raw.operationId === undefined ? "" : String(raw.operationId);
        if (operationId != "" && !isSafeToken(operationId, 96)) return null;
        var kind:String = raw.kind === undefined ? "terminal" : String(raw.kind);
        if (kind != "terminal" && kind != "close" && kind != "claim"
                && kind != "claim_batch") return null;
        var result:Object = {operationId:operationId, kind:kind,
            terminalState:String(terminalState)};
        if (raw.fingerprint !== undefined) {
            if (!isBoundedText(String(raw.fingerprint), MAX_RECEIPT_FINGERPRINT_LENGTH, true)) return null;
            result.fingerprint = String(raw.fingerprint);
        }
        if (raw.authorityRevision !== undefined) {
            if (!isCount(raw.authorityRevision)) return null;
            result.authorityRevision = Number(raw.authorityRevision);
        }
        if (raw.appliedCount !== undefined) {
            if (!isWhole(Number(raw.appliedCount)) || Number(raw.appliedCount) < 0
                    || Number(raw.appliedCount) > MAX_REWARD_SLOTS) return null;
            result.appliedCount = Number(raw.appliedCount);
        }
        if (raw.error !== undefined) {
            if (!isBoundedText(String(raw.error), 96, true)) return null;
            result.error = String(raw.error);
        }
        return result;
    }

    private static function normalizeTerminalMarker(raw:Object):Object {
        if (raw == null || !hasOnlyKeys(raw,
                ["v", "settlementId", "terminalState", "receipt"])
                || Number(raw.v) != 1 || !isSafeToken(String(raw.settlementId), 96)
                || (raw.terminalState != "claimed" && raw.terminalState != "abandoned"
                    && raw.terminalState != "error")) return null;
        var receipt:Object = normalizeTerminalReceipt(raw.receipt, String(raw.terminalState));
        if (receipt == null || !samePlainValue(raw.receipt, receipt, 0)) return null;
        return {v:1, settlementId:String(raw.settlementId),
            terminalState:String(raw.terminalState), receipt:receipt};
    }

    private static function isManifestSubset(candidate:Array, original:Array):Boolean {
        if (!(candidate instanceof Array) || !(original instanceof Array)
                || candidate.length > original.length) return false;
        var originalIndex:Number = 0;
        for (var i:Number = 0; i < candidate.length; i++) {
            var row:Object = candidate[i];
            while (originalIndex < original.length
                    && Number(original[originalIndex].slot) < Number(row.slot)) originalIndex++;
            if (originalIndex >= original.length
                    || Number(original[originalIndex].slot) != Number(row.slot)
                    || !samePlainValue(original[originalIndex].item, row.item, 0)) return false;
        }
        return true;
    }

    private static function sameManifest(left:Object, right:Object):Boolean {
        if (!(left instanceof Array) || !(right instanceof Array)
                || left.length != right.length) return false;
        for (var i:Number = 0; i < left.length; i++) {
            if (Number(left[i].slot) != Number(right[i].slot)
                    || !samePlainValue(left[i].item, right[i].item, 0)) return false;
        }
        return true;
    }

    private static function cloneSaveValue(value, depth:Number):Object {
        if (depth > 8) return null;
        if (value === null) return {success:true, value:null};
        var kind:String = typeof value;
        if (kind == "string") {
            if (!isBoundedText(String(value), MAX_RECEIPT_FINGERPRINT_LENGTH, true)) return null;
            return {success:true, value:String(value)};
        }
        if (kind == "number") {
            if ((Number(value) - Number(value)) != 0) return null;
            return {success:true, value:Number(value)};
        }
        if (kind == "boolean") return {success:true, value:value === true};
        if (kind != "object" || value === undefined) return null;
        if (value instanceof Array) {
            if (value.length > 64) return null;
            var arrayCopy:Array = [];
            for (var i:Number = 0; i < value.length; i++) {
                var child:Object = cloneSaveValue(value[i], depth + 1);
                if (child == null || child.success !== true) return null;
                arrayCopy.push(child.value);
            }
            return {success:true, value:arrayCopy};
        }
        var objectCopy:Object = {};
        var count:Number = 0;
        for (var key:String in value) {
            if (typeof value.hasOwnProperty == "function" && !value.hasOwnProperty(key)) continue;
            if (!isBoundedText(key, 64, false) || key.substr(0, 2) == "__"
                    || key == "constructor" || key == "prototype"
                    || key == "hasOwnProperty") return null;
            count++;
            if (count > 64) return null;
            child = cloneSaveValue(value[key], depth + 1);
            if (child == null || child.success !== true) return null;
            objectCopy[key] = child.value;
        }
        return {success:true, value:objectCopy};
    }

    private static function clonePlainValue(value, depth:Number) {
        var cloned:Object = cloneSaveValue(value, depth);
        return cloned == null || cloned.success !== true ? null : cloned.value;
    }

    private static function samePlainValue(left, right, depth:Number):Boolean {
        if (depth > 8 || typeof left != typeof right) return false;
        if (left === null || right === null || typeof left != "object") return left === right;
        var leftArray:Boolean = left instanceof Array;
        if (leftArray != (right instanceof Array)) return false;
        if (leftArray) {
            if (left.length != right.length) return false;
            for (var i:Number = 0; i < left.length; i++) {
                if (!samePlainValue(left[i], right[i], depth + 1)) return false;
            }
            return true;
        }
        var leftCount:Number = 0;
        for (var key:String in left) {
            if (typeof left.hasOwnProperty == "function" && !left.hasOwnProperty(key)) continue;
            leftCount++;
            if (!right.hasOwnProperty(key)
                    || !samePlainValue(left[key], right[key], depth + 1)) return false;
        }
        var rightCount:Number = 0;
        for (key in right) {
            if (typeof right.hasOwnProperty == "function" && !right.hasOwnProperty(key)) continue;
            rightCount++;
        }
        return leftCount == rightCount;
    }

    private static function isBoundedText(value:String, maximum:Number,
                                          allowEmpty:Boolean):Boolean {
        if (typeof value != "string" || value.length > maximum
                || (!allowEmpty && value.length < 1)) return false;
        for (var i:Number = 0; i < value.length; i++) {
            var code:Number = value.charCodeAt(i);
            if (code < 32 || code == 127 || (code >= 128 && code <= 159)) return false;
        }
        return true;
    }

    private static function isCount(value):Boolean {
        return typeof value == "number" && isWhole(Number(value))
            && Number(value) >= 0 && Number(value) <= MAX_SAFE_INTEGER;
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
            settlementId:_run.settlementId,
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
