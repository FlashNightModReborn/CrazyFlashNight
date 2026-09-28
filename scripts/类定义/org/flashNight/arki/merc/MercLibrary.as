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

    // mercenaries.json dialogues 的名字索引。世界副本的 [19] 现在由 MercSpawner.copyMercMeta
    // 补独立拷贝，副本上也读得到 对话，所以本索引与 [19].对话 等价；把两条通道收成一条要同步改
    // MercDialogueTest 的门数，留作独立清理。见 buildDialogueGroups 的取用点。
    private static var _dialoguesByName:Object = {};

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
        // 与池同步重建：JSON 里已删除的记录不能留下过期的指定对话
        _dialoguesByName = {};

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
            var merc:Array = buildMercData(raw);
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

    public static function buildMercData(raw:Object):Array {
        var merc:Array = new Array(20);
        var equipment:Object = raw.equipment;
        if (equipment == undefined) equipment = {};
        merc[0]  = raw.level;
        merc[1]  = raw.name;
        merc[2]  = raw.id;
        merc[3]  = raw.height;
        merc[4]  = raw.face == null ? "" : _root.脸型库[raw.face];
        merc[5]  = raw.hair == null ? "" : _root.发型库[raw.hair];
        merc[6]  = equipment.head       == null ? "" : equipment.head;
        merc[7]  = equipment.body       == null ? "" : equipment.body;
        merc[8]  = equipment.hand       == null ? "" : equipment.hand;
        merc[9]  = equipment.leg        == null ? "" : equipment.leg;
        merc[10] = equipment.foot       == null ? "" : equipment.foot;
        merc[11] = equipment.neck       == null ? "" : equipment.neck;
        merc[12] = equipment.primary    == null ? "" : equipment.primary;
        merc[13] = equipment.secondary1 == null ? "" : equipment.secondary1;
        merc[14] = equipment.secondary2 == null ? "" : equipment.secondary2;
        merc[15] = equipment.melee      == null ? "" : equipment.melee;
        merc[16] = equipment.gerenade   == null ? "" : equipment.gerenade;
        merc[17] = raw.gender;
        merc[18] = calculatePrice(raw.level);
        // [19] 是元数据子对象。字段名是公共契约（_root.同伴数据[i][19].XXX 多处引用），保留中文
        merc[19] = {是否杂交: false};
        if (raw.pricemultiplier) {
            merc[19].价格倍率 = raw.pricemultiplier;
        }
        if (raw.enhancement) {
            merc[19].装备强化度 = raw.enhancement;
        }
        if (raw.passive) {
            merc[19].被动技能 = raw.passive;
        }
        if (raw.equiplocked) {
            merc[19].装备锁定 = true;
        }
        var 性格配置:Object = normalizePersonality(raw.personality);
        if (性格配置 != undefined) {
            merc[19].性格 = 性格配置;
        }
        var 对话配置:Array = normalizeDialogues(raw.dialogues);
        if (对话配置 != undefined) {
            merc[19].对话 = 对话配置;
            _dialoguesByName[raw.name] = 对话配置;
        }
        return merc;
    }

    // 人格六维键。与 _root.生成随机人格 的维度名、MercPanelService 序列化顺序同源。
    private static var PERSONALITY_DIMS:Array = ["勇气", "技术", "经验", "反应", "智力", "谋略"];

    /**
     * mercenaries.json 顶层 personality → merc[19].性格 的归一化：只认六维、只收数值，
     * 并夹进 [0, 1]（下游 计算AI参数 的线性公式按该值域设计，越界值会放大成不可预期的 AI 行为）。
     * 缺省与显式 null 都算未配置（装备列用 null 表示"不配"，Number(null) 却是 0）。
     * 无有效维度时返回 undefined，让未配置的佣兵保持 生成随机人格 的结果。
     */
    public static function normalizePersonality(raw:Object):Object {
        if (raw == undefined || typeof raw != "object") return undefined;
        var out:Object = undefined;
        for (var i:Number = 0; i < PERSONALITY_DIMS.length; i++) {
            var dim:String = PERSONALITY_DIMS[i];
            var authored = raw[dim];
            if (authored == undefined) continue;
            var value:Number = Number(authored);
            if (isNaN(value)) continue;
            if (out == undefined) out = {};
            out[dim] = value < 0 ? 0 : (value > 1 ? 1 : value);
        }
        return out;
    }

    /**
     * 把数据侧性格覆写合并进已有人格向量。必须 mutate 而非替换：UnitAIData.personality
     * 与面板投影持同一引用，换对象会让战斗侧 AI 读到陈旧向量（配置人形怪AI 同一约定）。
     * 返回是否合并过维度，调用方据此决定是否重算 计算AI参数 派生参数。
     */
    public static function mergePersonalityTraits(personality:Object, authored:Object):Boolean {
        if (personality == undefined || authored == undefined) return false;
        var merged:Boolean = false;
        for (var i:Number = 0; i < PERSONALITY_DIMS.length; i++) {
            var dim:String = PERSONALITY_DIMS[i];
            if (authored[dim] != undefined) {
                personality[dim] = authored[dim];
                merged = true;
            }
        }
        return merged;
    }

    /**
     * mercenaries.json 顶层 dialogues → merc[19].对话 的归一化。一条台词写成纯字符串，
     * 或写成 {text, expression} 指定表情；expression 缺省为 "普通"，与 组装单次对话
     * 对无表情台词的默认值一致。非法条目只丢弃自身；整表无有效台词时返回 undefined，
     * 让该佣兵回落到"按人格主维度抽公共台词"。
     *
     * 文本约束：mercenaries.json 由 LiteJSON 解析，它按 indexOf('"') 扫字符串、不处理
     * 转义，所以台词里出现半角双引号或反斜杠会让整份 JSON 解析失败（全佣兵池丢失）。
     * 需要引用语气时用全角「」或“”。scripts/run-merc-loadout-tests.ps1 有静态门守这条。
     */
    public static function normalizeDialogues(raw:Object):Array {
        if (raw == undefined || !(raw instanceof Array)) return undefined;
        var out:Array = [];
        for (var i:Number = 0; i < raw.length; i++) {
            var entry = raw[i];
            var text = entry;
            var expression = undefined;
            if (typeof entry == "object" && entry != null) {
                text = entry.text;
                expression = entry.expression;
            }
            if (typeof text != "string" || text == "") continue;
            out.push({
                文本: text,
                表情: (typeof expression == "string" && expression != "") ? expression : "普通"
            });
        }
        return out.length > 0 ? out : undefined;
    }

    /** 按库记录名取指定对话；未配置返回 undefined。与副本 [19].对话 的关系见 _dialoguesByName。 */
    public static function dialoguesByName(mercName:String):Array {
        return _dialoguesByName[mercName];
    }

    /**
     * 指定对话 → 默认对话 的轮次数组。每条台词自成一组：对话按钮的语义是
     * 「洗牌 + 按 对话index 整组播放」（NativeMenuBridge.runAction），所以一组一条
     * 才是"每点一次换一句"；把全部台词塞进同一组会每次点按整段重放。
     * 第 3 位 "主角模板" 与第 5 位 target 必须成对出现：立绘解析见到
     * char=="主角模板" 且 target 为空时会去取主角外观（NativeDialogueAppearance）。
     */
    public static function buildDialogueGroups(lines:Array, mercName:String, target:MovieClip):Array {
        var groups:Array = [];
        for (var i:Number = 0; i < lines.length; i++) {
            groups[i] = [[mercName, "佣兵", "主角模板", lines[i].文本, lines[i].表情, target]];
        }
        return groups;
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
