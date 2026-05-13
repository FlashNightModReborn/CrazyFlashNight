import org.flashNight.arki.merc.*;
import org.flashNight.arki.scene.StageManager;

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

    public static function enter(lineup:Array):Void {
        if (lineup != undefined) {
            enterArenaCommon();
        }
    }

    public static function close():Void {
        _root.发布请求 = false;
        _root.决斗场进入中 = false;
        StageManager.instance.clear();
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
    public static function commitArena():Void {
        if (_root.出阵人员 == undefined || _root.出阵人员.length == 0) return;
        if (_root.当前佣兵重用数 <= _root.竞技场佣兵重用基数) {
            _root.当前佣兵重用数++;
        } else {
            MercLibrary.refreshPool(bumpReuseLimit, undefined);
        }
        enterArenaCommon();
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

    private static function enterArenaCommon():Void {
        _root.金钱 -= _root.押金;
        _root.最上层发布文字提示("已扣除押金" + _root.押金);
        _root.当前通关的关卡 = "";
        _root.当前关卡名 = "DEATH MATCH角斗场";
        _root.场景进入位置名 = "出生地";
        _root.敌人同伴数 = _root.出阵人员.length;
        _root.敌人同伴数据 = _root.出阵人员;
        _root.淡出动画.淡出跳转帧("wuxianguotu_1");
    }
}
