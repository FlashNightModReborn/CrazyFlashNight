import org.flashNight.arki.merc.*;
import org.flashNight.arki.scene.StageManager;
import org.flashNight.arki.item.PlayerAssetTransaction;

/*
 * 决斗场+佣兵库请求链。
 *
 * Step 5 改动：
 *   - 干掉 _root.佣兵请求成功/失败/中回调 三个全局槽位 + 历史 typo
 *     `if (成功回调 != undefined) 失败回调 = ...`。改成 callback 风格。
 *   - 合并 pickRandom 的 selection 逻辑为 selectByExpression。
 *   - 共享的"扣押金 + 跳转决斗场关卡"块抽成 enterArenaCommon。
 *   - 库存查询走 MercLibrary.hasEnoughFor / requireExpression / loadMoreByExpression。
 *   - 删除 enterFallback 死路径：mercs_list 现规模 (202 条) + 同伴数据上限 (5)
 *     使 hasEnoughFor 数学上不可能返回 false。原 25 条 lvl 1-25 fallback
 *     数据 (_root.佣兵不足时出阵人员) 同步删除。
 *
 * 注意未改：重用计数 _root.竞技场佣兵重用基数 单调递增机制——意图存疑（可能是 bug，
 * 也可能是"渐进降低补充频率"的设计），保留原行为。
 */
class org.flashNight.arki.merc.ArenaController {
    private static var _pendingStageStartToken:String = "";

    public static function enter(lineup:Array):Void {
        if (lineup != undefined) {
            enterArenaCommon();
        }
    }

    public static function close():Void {
        _root.发布请求 = false;
        _root.决斗场进入中 = false;
        cancelPendingStageStart();
        StageManager.instance.clear();
    }

    /** 只撤销本 ArenaController 尚未被首个 initStage 消费的 exact reservation。 */
    public static function cancelPendingStageStart(expectedToken:String):Boolean {
        if (_pendingStageStartToken == "") return false;
        if (expectedToken != undefined && expectedToken != ""
                && _pendingStageStartToken !== expectedToken) return false;
        var token:String = _pendingStageStartToken;
        _pendingStageStartToken = "";
        if (StageManager.instance != null
                && StageManager.instance.abortPreparedStage(token)) return true;
        return org.flashNight.arki.scene.StageRunSession.cancelStageStart(token);
    }

    public static function pickRandom(expr:String):Void {
        var lineup:Array = selectByExpression(expr, _root.可雇佣兵);
        if (_root.决斗场进入中 == true) {
            enter(lineup);
            _root.决斗场进入中 = false;
        }
    }

    /**
     * 仅抽阵容，写 _root.出阵人员，**不**碰 reuse 计数 / pool 刷新 / 转场。
     * Web 预览路径用：抽完取走 _root.出阵人员 序列化给用户看，可以无限重抽。
     * 返回 true = 成功（库存够），false = 库存不足。
     */
    public static function rollPreview(expr:String):Boolean {
        if (!MercLibrary.hasEnoughFor(expr)) return false;
        selectByExpression(expr, _root.可雇佣兵);
        return true;
    }

    /**
     * 提交当前 _root.出阵人员（即上一次 rollPreview 写下的阵容）到进场链。
     * 含 reuse 计数 / pool 刷新 / 扣押金 / 跳转 wuxianguotu_1，等价于 requestOpponent 的后半段。
     * 调用前必须先 rollPreview 成功；空阵容直接 no-op。
     */
    public static function commitArena():Boolean {
        if (_root.出阵人员 == undefined || _root.出阵人员.length == 0
                || !canEnterArenaTransition()) return false;
        _root.角斗场对手类型 = "merc"; // 守 enterArenaCommon 分叉，防上一场 roster 残留
        _root.角斗场roster状态 = undefined;
        _root.角斗场对手禁收益 = false;
        if (_root.当前佣兵重用数 <= _root.竞技场佣兵重用基数) {
            _root.当前佣兵重用数++;
        } else {
            MercLibrary.refreshPool(bumpReuseLimit, undefined);
        }
        return enterArenaCommon();
    }

    /**
     * 提交元战队 / 混编 roster 阵容进场。squad = [{兵种:"兵种N", 等级:L} | {类型:"merc", 佣兵:[...]}, ...]。
     * 调用前须先 prepareArenaStage（载入关卡数据 + 押金/奖金）。不碰佣兵 reuse/pool 计数。
     * 对手经帧脚本 _root.加载角斗场怪物 读 _root.角斗场roster阵容 逐个生成。
     */
    public static function commitRoster(squad:Array):Boolean {
        if (squad == undefined || squad.length == 0
                || !canEnterArenaTransition()) return false;
        _root.角斗场对手类型 = "roster";
        _root.角斗场roster状态 = undefined;
        _root.角斗场roster阵容 = squad;
        return enterArenaCommon();
    }

    /**
     * 提交爬升模式（Phase 3）：势力主题无限爬升 + 奖池押注。
     * pool = [{type:"兵种N", minLevel, maxLevel, weight}, ...]（web 从该势力 roster 下发，AS2 每波采样）。
     * 战斗循环 / 压力板决策 / 奖池经济全在 关卡回调函数（_root.角斗场爬升* 一组函数）里自管。
     * 调用前须先 prepareArenaStage（押金/奖金/场景预载）。reward 作为奖池首波基数。
     */
    public static function commitEscalation(faction:String, pool:Array, baseCount:Number, baseLevelMin:Number, baseLevelMax:Number, deposit:Number, reward:Number, maxWaves:Number):Boolean {
        if (pool == undefined || pool.length == 0
                || !canEnterArenaTransition()) return false;
        _root.角斗场对手类型 = "escalation";
        _root.角斗场roster状态 = undefined;
        _root.角斗场对手禁收益 = false;
        _root.角斗场爬升 = {
            active:       true,
            faction:      faction,
            pool:         pool,
            baseCount:    baseCount,
            baseLevelMin: baseLevelMin,
            baseLevelMax: baseLevelMax,
            baseReward:   reward,                       // = 波奖励基准（对标等级×base对手数×500，web 算）
            最大波数:     (maxWaves > 0) ? maxWaves : 10, // 波数上限（小5/大10/联军15），缺省 10
            round:        0,
            pot:          0,
            phase:        "combat",
            pollFrame:    0
        };
        return enterArenaCommon();
    }

    /**
     * 角斗场场景数据预载 + 押金/奖金/难度上下文（merc 与 roster 共用）。
     * 复现「角斗场选择挑战者」帧的 stage 预载（Web 直跳关必须手动做）。
     * onLoaded/onLoadError 透传给 _root.载入关卡数据；返回 false = StageInfoDict 缺 "DEATH MATCH角斗场"（调用方应报错中止）。
     */
    public static function prepareArenaStage(deposit:Number, reward:Number, difficulty:String,
            onLoaded:Function, onLoadError:Function, skipStageRunReservation:Boolean):Boolean {
        var stageInfo:Object = _root.StageInfoDict ? _root.StageInfoDict["DEATH MATCH角斗场"] : undefined;
        if (stageInfo == undefined || stageInfo.url == undefined || String(stageInfo.url) == "") return false;
        if (typeof _root.载入关卡数据 != "function") return false;
        var startToken:String = org.flashNight.arki.scene.StageRunSession.reserveStageStart(
            skipStageRunReservation === true ? "arena_calibration" : "arena",
            "DEATH MATCH角斗场", difficulty);
        if (startToken == "") return false;
        _pendingStageStartToken = startToken;
        var settled:Boolean = false;
        var failOnce:Function = function():Void {
            if (settled) return;
            settled = true;
            if (startToken != "" && _pendingStageStartToken == startToken) {
                cancelPendingStageStart(startToken);
            } else if (startToken != "") {
                if (StageManager.instance != null) {
                    StageManager.instance.abortPreparedStage(startToken);
                }
                org.flashNight.arki.scene.StageRunSession.cancelStageStart(startToken);
            }
            if (typeof onLoadError == "function") onLoadError(startToken);
        };
        try {
            _root.载入关卡数据(String(stageInfo.Type || "无限过图"), String(stageInfo.url),
                function(data:Object):Void {
                    if (settled) return;
                    if (startToken != ""
                            && !org.flashNight.arki.scene.StageRunSession
                                .isStageStartReservationValid(startToken)) {
                        failOnce();
                        return;
                    }
                    try {
                        if (typeof onLoaded == "function") onLoaded(data, startToken);
                    } catch (loadedCallbackError) {
                        trace("[ArenaController] prepared-stage callback failed: "
                            + loadedCallbackError);
                        failOnce();
                        return;
                    }
                    settled = true;
                },
                function():Void {
                    failOnce();
                }, startToken, skipStageRunReservation === true);
        } catch (loadError) {
            failOnce();
            return true;
        }
        return true;
    }

    /** XML/TimePool 与调用方 final gate 都成功后，才提交角斗场转场上下文。 */
    public static function applyPreparedArenaContext(
            deposit:Number, reward:Number, difficulty:String):Boolean {
        var token:String = _pendingStageStartToken;
        if (token == "" || !org.flashNight.arki.scene.StageRunSession
                .isStageStartReservationValid(token)) return false;
        var difficultyLevel:Number;
        if (difficulty != undefined && difficulty != "") {
            if (typeof _root.计算难度等级 != "function") return false;
            try {
                difficultyLevel = _root.计算难度等级(difficulty);
            } catch (difficultyError) {
                return false;
            }
        }
        _root.关卡类型 = "无限过图";
        _root.关卡路径 = String(
            _root.StageInfoDict["DEATH MATCH角斗场"].url || "");
        _root.押金 = deposit;
        _root.角斗场奖金 = reward;
        if (difficulty != undefined && difficulty != "") {
            _root.当前关卡难度 = difficulty;
            _root.难度等级 = difficultyLevel;
        }
        return true;
    }

    public static function requestOpponent(expr:String):Void {
        if (!rollPreview(expr)) {
            // mercs_list 当前规模下数学上不可达；保留为防御性失败路径（明确提示而非
            // 静默切到错档对手）。如未来扩 佣兵个数限制 或缩 mercs_list 才可能触发。
            _root.最上层发布文字提示("佣兵库存不足");
            return;
        }
        commitArena();
    }

    public static function bumpReuseLimit():Void {
        _root.竞技场佣兵重用基数 += _root.重用基数成长率;
        _root.当前佣兵重用数 = 0;
    }

    /**
     * 异步请求佣兵库满足条件。callback 风格替代历史的三全局槽位。
     *   callback(response): response.success 表示满足
     *
     * 等待 UI（_root.等待mc）由本函数管理：开始时显示，回调时隐藏。
     * 如果调用方需要更精细的控制，直接用 MercLibrary.requireExpression。
     */
    public static function requestMerc(expr:String, callback:Function):Void {
        if (MercLibrary.hasEnoughFor(expr)) {
            if (callback) callback({success: true});
            return;
        }
        _root.等待mc._visible = true;
        MercLibrary.requireExpression(expr, function(response:Object):Void {
            _root.等待mc._visible = false;
            if (callback) callback(response);
        });
    }

    // ─── 内部辅助 ─────────────────────────────────────────────────────────

    /**
     * 按表达式在 dataSource 中按段抽取出阵号，并写入 _root.出阵人员。
     * 返回选中的索引数组（外部可能需要做"是否非空"判断）。
     */
    private static function selectByExpression(expr:String, dataSource:Array):Array {
        var queryTable:Array = MercLibrary.parseExpression(expr).slice();
        var lineup:Array = [];
        for (var i:Number = 0; i < queryTable.length; i++) {
            var available:Array = [];
            for (var j:Number = 0; j < dataSource.length; j++) {
                if (dataSource[j][0] >= queryTable[i][1]
                    && dataSource[j][0] <= queryTable[i][2]) {
                    available.push(j);
                }
            }
            while (queryTable[i][3] > 0) {
                var pick:Number = random(available.length);
                lineup.push(available[pick]);
                available.splice(pick, 1);
                queryTable[i][3]--;
            }
        }
        _root.出阵人员 = [];
        for (var k:Number = 0; k < lineup.length; k++) {
            _root.出阵人员.push(dataSource[lineup[k]]);
        }
        return lineup;
    }

    private static function canEnterArenaTransition():Boolean {
        var deposit:Number = Number(_root.押金);
        var money:Number = Number(_root.金钱);
        return _root.淡出动画 != undefined
            && typeof _root.淡出动画.淡出跳转帧 == "function"
            && !isNaN(deposit) && deposit != Infinity && deposit != -Infinity && deposit >= 0
            && !isNaN(money) && money != Infinity && money != -Infinity && money >= deposit;
    }

    private static function enterArenaCommon():Boolean {
        // token 在首个 StageManager.initStage 真正 begin 之前始终保留；
        // commit/fade 抛错时 ArenaPanelService 仍可 exact cancel。
        if (!canEnterArenaTransition()) return false;
        if (_root.角斗场对手类型 == "escalation") {
            if (_root.角斗场爬升 == undefined || _root.角斗场爬升.pool == undefined
                    || _root.角斗场爬升.pool.length == 0) return false;
        } else if (_root.角斗场对手类型 == "roster") {
            if (_root.角斗场roster阵容 == undefined
                    || _root.角斗场roster阵容.length == 0) return false;
        } else if (_root.出阵人员 == undefined || _root.出阵人员.length == 0) {
            return false;
        }
        var moneyBefore:Number = Number(_root.金钱);
        var dirtyBefore = _root.存档系统 != undefined
            ? _root.存档系统.dirtyMark : undefined;
        try {
            _root.金钱 -= _root.押金;
            if (_root.存档系统 != undefined) _root.存档系统.dirtyMark = true;
            _root.当前通关的关卡 = "";
            _root.当前关卡名 = "DEATH MATCH角斗场";
            _root.场景进入位置名 = "出生地";
            if (_root.角斗场对手类型 == "escalation") {
                // 爬升模式自管波次计数（每波刷怪后自行维护 僵尸型敌人总个数），此处占位即可
                _root.敌人同伴数 = 0;
            } else if (_root.角斗场对手类型 == "roster") {
                // 怪物经 加载角斗场怪物 读 _root.角斗场roster阵容 生成；敌人同伴数=队伍规模供判胜计数
                _root.敌人同伴数 = _root.角斗场roster阵容.length;
            } else {
                _root.敌人同伴数 = _root.出阵人员.length;
                _root.敌人同伴数据 = _root.出阵人员;
            }
            // 抑制基地车库选关门重触发（复刻 StageSelectPanelService 进关后的场景门去抖）。
            if (_root.场景转换函数 != undefined && _root.帧计时器 != undefined) {
                _root.场景转换函数.上次切换帧数 = _root.帧计时器.当前帧数;
            }
            _root.淡出动画.淡出跳转帧("wuxianguotu_1");
        } catch (transitionError) {
            _root.金钱 = moneyBefore;
            if (_root.存档系统 != undefined) {
                _root.存档系统.dirtyMark = dirtyBefore;
            }
            throw transitionError;
        }
        try {
            org.flashNight.arki.item.PlayerAssetTransaction.recordCurrencyDeltas(
                -Number(_root.押金), 0,
                {source:"arena_entry", reason:"deposit", mergeScope:"operation"});
        } catch (projectionError) {
            trace("[ArenaController] entry currency projection failed: "
                + projectionError);
        }
        if (typeof _root.最上层发布文字提示 == "function") {
            try { _root.最上层发布文字提示("已扣除押金" + _root.押金); }
            catch (messageError) {
                trace("[ArenaController] entry message failed: " + messageError);
            }
        }
        return true;
    }
}
