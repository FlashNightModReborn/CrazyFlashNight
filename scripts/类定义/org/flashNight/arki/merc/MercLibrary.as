import org.flashNight.arki.merc.*;
import org.flashNight.naki.Sort.InsertionSort;
import org.flashNight.neur.Server.DataQueryService;

/*
 * MercLibrary：佣兵数据访问层。
 *
 * 这是 C# 迁移的关键解耦缝。当前职责：
 *   1. Bundle cache：teams / names / dialogues / pool（通过 merc_bundle DataQuery 异步加载）
 *   2. Marshalling：rawList → mercData[20]（loadFromList）
 *   3. 库存查询：parseExpression / query / hasEnoughFor
 *   4. 库存补充：loadMore / loadMoreByExpression / requireExpression（callback 风格）
 *   5. 价格计算：calculatePrice
 *
 * 当 mercs_list 迁到 launcher 时，只需把 loadMore 内部的 `_root.mercs_list` 读取
 * 改成 `DataQueryService.query("mercs_list", ...)`。其余调用方零改动。
 *
 * 数据存储约束：
 *   - _root.可雇佣兵 / _root.隐藏的可雇佣兵 仍是公共可变数组（被 XML 直接读写），
 *     MercLibrary 对它们读写，不做"私有副本"。这是兼容性边界，不下沉。
 *   - bundle 数据是私有缓存（_bundle），只读访问通过 MercLibrary.bundle。
 *     Hybridizer / Spawner 直接读 MercLibrary.bundle，不再读 _root.X。
 *
 * 表达式格式：`#col@lo-hi%count,...`
 *   col   佣兵数据的列号（mercData 数组索引，0=等级，1=名字，...）
 *   lo-hi 列值的下/上限
 *   count 该条目的目标数量
 */
class org.flashNight.arki.merc.MercLibrary {

    // ─── Bundle cache ─────────────────────────────────────────────────────
    private static var _bundleLoaded:Boolean = false;
    private static var _bundleLoading:Boolean = false;
    private static var _bundlePending:Array = [];
    private static var _bundle:Object;

    public static function get bundle():Object {
        return _bundle;
    }

    /**
     * 异步确保 bundle 已加载。已加载则立即回调；正在加载则排队；未加载则触发查询。
     * Session 级缓存，不主动失效（数据是配置常量，几 KB 级，无需引用计数）。
     *
     * callback 签名: function(response:Object):Void
     *   response.success / response.result / response.error 与 DataQueryService 一致
     */
    public static function ensureBundleLoaded(callback:Function):Void {
        if (_bundleLoaded) {
            if (callback) callback({success: true, result: _bundle});
            return;
        }
        if (callback) _bundlePending.push(callback);
        if (_bundleLoading) return;
        _bundleLoading = true;
        DataQueryService.query("merc_bundle", null, function(response:Object):Void {
            _bundleLoading = false;
            if (response.success) {
                _bundle = response.result;
                _bundleLoaded = true;
            }
            var pending:Array = _bundlePending;
            _bundlePending = [];
            for (var i:Number = 0; i < pending.length; i++) {
                pending[i](response);
            }
        });
    }

    // ─── Marshalling: rawList → mercData[20] ──────────────────────────────

    /**
     * 从 raw 数据源（当前是 _root.mercs_list）构建 _root.可雇佣兵 / _root.隐藏的可雇佣兵。
     * 已雇佣的（_root.同伴数据 中存在）会被去重跳过。
     *
     * 迁移点：未来 rawList 可来自 launcher data_query，而非 _root.mercs_list。
     * 调用方只需把 loadMore 中的数据源读取改了即可，本函数不变。
     */
    public static function loadFromList(rawList):Void {
        _root.可雇佣兵 = [];
        _root.隐藏的可雇佣兵 = [];

        var seen:Object = {};
        for (var i:Number = 0; i < _root.佣兵个数限制; i++) {
            if (_root.同伴数据[i][1] && _root.同伴数据[i][2]) {
                seen[_root.同伴数据[i][2]] = _root.同伴数据[i][1];
            }
        }

        for (var key:String in rawList) {
            var raw:Object = rawList[key];
            if (seen[raw.id] && seen[raw.id] == raw.name) {
                continue;
            }
            var merc:Array = new Array(20);
            merc[0]  = raw.level;
            merc[1]  = raw.name;
            merc[2]  = raw.id;
            merc[3]  = raw.height;
            merc[4]  = raw.face == null ? "" : _root.脸型库[raw.face];
            merc[5]  = raw.hair == null ? "" : _root.发型库[raw.hair];
            merc[6]  = raw.equipment.head       == null ? "" : raw.equipment.head;
            merc[7]  = raw.equipment.body       == null ? "" : raw.equipment.body;
            merc[8]  = raw.equipment.hand       == null ? "" : raw.equipment.hand;
            merc[9]  = raw.equipment.leg        == null ? "" : raw.equipment.leg;
            merc[10] = raw.equipment.foot       == null ? "" : raw.equipment.foot;
            merc[11] = raw.equipment.neck       == null ? "" : raw.equipment.neck;
            merc[12] = raw.equipment.primary    == null ? "" : raw.equipment.primary;
            merc[13] = raw.equipment.secondary1 == null ? "" : raw.equipment.secondary1;
            merc[14] = raw.equipment.secondary2 == null ? "" : raw.equipment.secondary2;
            merc[15] = raw.equipment.melee      == null ? "" : raw.equipment.melee;
            merc[16] = raw.equipment.gerenade   == null ? "" : raw.equipment.gerenade;
            merc[17] = raw.gender;
            merc[18] = calculatePrice(raw.level);
            // [19] 是元数据子对象。字段名是公共契约（_root.同伴数据[i][19].XXX 多处引用），保留中文。
            // raw 外观 id 作为 Web 面板兜底保留：若发型/脸型库异步加载晚于佣兵池刷新，
            // merc[4]/merc[5] 可能为空，但 Web 仍可按 manifest 的 appearance 映射恢复头像。
            merc[19] = {是否杂交: false};
            if (raw.face != null) merc[19].脸型ID = raw.face;
            if (raw.hair != null) merc[19].发型ID = raw.hair;
            if (raw.pricemultiplier) {
                merc[19].价格倍率 = raw.pricemultiplier;
            }
            if (raw.enhancement) {
                merc[19].装备强化度 = raw.enhancement;
            }
            if (raw.passive) {
                merc[19].被动技能 = raw.passive;
            }
            if (raw.hidden) {
                merc[19].隐藏 = raw.hidden;
                _root.隐藏的可雇佣兵.push(merc);
            } else {
                _root.可雇佣兵.push(merc);
            }
        }
        InsertionSort.sortOn(_root.可雇佣兵, 0, Array.NUMERIC);
        _root.可雇佣兵 = _root.可雇佣兵.concat(_root.隐藏的可雇佣兵);
        // 池索引变了，权重缓存必须重算，否则 pickRandomMercIndex 会读到 stale weights。
        MercSpawner.invalidateIndexCache();
    }

    /**
     * 重新加载完整佣兵库。当前数据源是 _root.mercs_list（legacy XML loader 装填）。
     * 迁移点：把这里改成 DataQueryService.query("mercs_list", ...) 即可。
     */
    public static function refreshPool(callback:Function, callbackArg):Void {
        loadFromList(_root.mercs_list);
        if (callback != undefined) {
            callback(callbackArg);
        }
    }

    // ─── Query / Parsing ───────────────────────────────────────────────────

    /**
     * 解析查询表达式 `#col@lo-hi%count,...`
     * 返回 [[col, lo, hi, count], ...]
     *
     * 注：col 字段保留是为了表达式语法兼容（Symbol 3394 硬编码 #0），
     * 但 query / selectByExpression 现在固定按 mercData[0]（等级）筛，col 实际不读。
     * 多 clause（逗号分段）也保留解析能力，当前唯一调用方传 1 段。
     */
    public static function parseExpression(expr:String):Array {
        var queryTable:Array = [];
        var clauses:Array = expr.split(",");
        for (var i:Number = 0; i < clauses.length; i++) {
            var head:Array = clauses[i].split("@");
            var tail:Array = head[1].split("%");
            queryTable.push([
                Number(head[0].split("#")[1]),
                Number(tail[0].split("-")[0]),
                Number(tail[0].split("-")[1]),
                Number(tail[1])
            ]);
        }
        return queryTable;
    }

    /**
     * 在 _root.可雇佣兵 中按表达式扣减缺额。返回第一个仍不足的查询条目（undefined 表示全部满足）。
     * 列固定为 0（等级）。
     */
    public static function query(expr:String) {
        var queryTable:Array = parseExpression(expr);
        for (var i:Number = 0; i < _root.可雇佣兵.length; i++) {
            for (var j:Number = 0; j < queryTable.length; j++) {
                if (queryTable[j][3] > 0) {
                    if (_root.可雇佣兵[i][0] >= queryTable[j][1]
                        && _root.可雇佣兵[i][0] <= queryTable[j][2]) {
                        queryTable[j][3]--;
                        break;
                    }
                }
            }
        }
        for (var k:Number = 0; k < queryTable.length; k++) {
            if (queryTable[k][3] > 0) {
                return queryTable[k];
            }
        }
        return undefined;
    }

    public static function hasEnoughFor(expr:String):Boolean {
        return query(expr) == undefined;
    }

    /**
     * 异步确保佣兵库满足表达式。
     *   - 库存够 → 立即 callback({success: true})
     *   - 不够 → refreshPool 一次后再判定
     *     - 仍不够 → callback({success: false, miss: queryEntry})
     *
     * 一次性 retry（不再无限递归）：未来 C# 数据源若返回 partial/empty/error，
     * 不会被卡死在等待 UI 上。
     */
    public static function requireExpression(expr:String, callback:Function):Void {
        var miss = query(expr);
        if (miss == undefined) {
            if (callback) callback({success: true});
            return;
        }
        refreshPool(function():Void {
            var miss2 = query(expr);
            if (miss2 == undefined) {
                if (callback) callback({success: true});
            } else {
                if (callback) callback({success: false, miss: miss2});
            }
        }, undefined);
    }

    // ─── Pricing ──────────────────────────────────────────────────────────

    public static function calculatePrice(level):Number {
        var lvl:Number = Number(level);
        var price:Number = 0;
        if (_root.isEasyMode() == true) {
            price = lvl * _root.基础身价值;
        } else if (_root.isChallengeMode() == true) {
            price = lvl * 15 * _root.基础身价值;
        } else if (lvl >= 50) {
            price = lvl * 25 * _root.基础身价值 - 1000 * _root.基础身价值;
        } else if (lvl >= 10) {
            price = lvl * 5 * _root.基础身价值 - 20 * _root.基础身价值;
        } else {
            price = 2.5 * _root.基础身价值 + lvl * 2.5 * _root.基础身价值;
        }
        return Number(price);
    }
}
