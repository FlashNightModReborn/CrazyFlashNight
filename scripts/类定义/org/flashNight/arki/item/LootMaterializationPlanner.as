import org.flashNight.arki.item.BaseItem;
import org.flashNight.arki.item.DropLuckRoller;
import org.flashNight.arki.item.ItemUtil;
import org.flashNight.arki.item.itemCollection.ArrayInventory;
import org.flashNight.naki.RandomNumberEngine.LinearCongruentialEngine;

/**
 * Web 地图资源箱的一次抽取、可重入物化 journal。
 *
 * 校验在任何随机推进前完成；每条规则的命中、数量和 exact BaseItem 都先追加到计划，
 * 再写入隔离 inventory，最后才一次提交源规则总数并清空 target.掉落物。roll/create/add
 * 任一边界失败都保留同一计划供下一次互动继续，不重滚、不复制物品、不提前扣总数。
 */
class org.flashNight.arki.item.LootMaterializationPlanner {
    // v2 删除 rollout marker 冻结，并把成对缺省的数量归一写入私有 descriptor。
    private static var JOURNAL_VERSION:Number = 2;
    private static var JOURNAL_FIELD:String = "__cf7WebLootMaterialization";
    // 与 Host/Web 战利品面板能力边界保持一致；超界正网格由 service fail-closed。
    private static var MAX_CAPACITY:Number = 64;
    private static var MAX_SAFE_INTEGER:Number = 9007199254740991;
    // AVM1 全局 random(n) 的正有符号 31 位上界；span=max-min+1 必须落在此范围。
    private static var MAX_RANDOM_SPAN:Number = 2147483647;
    // 当前地图箱唯一 outcome-affecting bonus 为逆向技能（满级 10 × 0.05）。
    private static var MAX_LOOT_LUCK_BONUS:Number = 0.5;

    private static var _testFailureStage:String = "";
    private static var _testFailureRuleIndex:Number = -1;

    public static function materialize(target:Object):Object {
        if (target == null) return {success:false, error:"missing_target"};

        var journal:Object = target[JOURNAL_FIELD];
        if (journal != undefined) {
            if (journal.version !== JOURNAL_VERSION || journal.target !== target) {
                return {success:false, error:"materialization_journal_conflict"};
            }
            if (journal.success === true || journal.terminalFailure === true) return journal;
            return resume(target, journal);
        }

        journal = {
            version:JOURNAL_VERSION,
            target:target,
            success:false,
            terminalFailure:false,
            error:"validation_failed",
            phase:"VALIDATING",
            rawDrops:null,
            rules:[],
            entries:[],
            slots:null,
            inventory:null,
            totalsApplied:false
        };
        target[JOURNAL_FIELD] = journal;
        try {
            _global.ASSetPropFlags(target, [JOURNAL_FIELD], 1, false);
        } catch (flagError) {
        }

        if (!initialize(target, journal)) return journal;
        return resume(target, journal);
    }

    /**
     * 供 direct / break 路径在任何掉落或随机推进前复用同一份规则契约。
     * 该方法只描述并校验源规则，不归一、写回或消耗 target 数据。
     */
    public static function validateDropRules(rawDrops:Object):Object {
        var described:Object = describeSourceRules(rawDrops, 0);
        if (!described.success) {
            return {success:false, error:described.error};
        }
        return {success:true, error:"", ruleCount:described.sourceRules.length};
    }

    private static function initialize(target:Object, journal:Object):Boolean {
        var cap:Number = Number(target.row) * Number(target.col);
        if (typeof target.row != "number" || typeof target.col != "number"
                || target.row <= 0 || target.col <= 0
                || Math.floor(target.row) != target.row || Math.floor(target.col) != target.col
                || cap < 1 || cap > MAX_CAPACITY) {
            fail(journal, "invalid_capacity", true);
            return false;
        }

        var rawDrops:Object = target.掉落物;
        var described:Object = describeSourceRules(rawDrops, cap);
        if (!described.success) {
            fail(journal, described.error, true);
            return false;
        }
        var sourceRules:Array = described.sourceRules;
        var descriptors:Array = described.descriptors;

        // DropLuckRoller 在地图箱路径只读取逆向 luck bonus；数量抽取不读取任何
        // luck/bonus。这里在 slot/roll/quantity 任一随机推进前冻结 bonus 与 PRD 引擎。
        var luckBonus:Number = Number(DropLuckRoller.getLuckBonus());
        if (typeof luckBonus != "number" || isNaN(luckBonus)
                || luckBonus < 0 || luckBonus > MAX_LOOT_LUCK_BONUS) {
            fail(journal, "invalid_luck_bonus", true);
            return false;
        }
        var prdEngine:Object = _root.dropPRDEngine;
        for (var descriptorIndex:Number = 0;
                descriptorIndex < descriptors.length; descriptorIndex++) {
            if (descriptors[descriptorIndex].hasProbability
                    && (prdEngine == null || typeof prdEngine.roll != "function"
                        || typeof prdEngine.getState != "function")) {
                fail(journal, "prd_unavailable", true);
                return false;
            }
        }

        journal.rawDrops = rawDrops;
        journal.rawDropsIsArray = rawDrops instanceof Array;
        journal.rawDropsLength = sourceRules.length;
        journal.rules = descriptors;
        journal.row = Number(target.row);
        journal.col = Number(target.col);
        journal.capacity = cap;
        journal.presetName = String(target.presetName);
        journal.luckBonus = luckBonus;
        journal.prdEngine = prdEngine;
        journal.inventory = new ArrayInventory(null, cap);
        journal.phase = "VALIDATED";
        journal.error = "";
        return true;
    }

    private static function describeSourceRules(rawDrops:Object, maxRules:Number):Object {
        var sourceRules:Array = [];
        if (rawDrops instanceof Array) {
            // rawDrops 保留原对象用于 retry identity proof；另复制规则引用到强类型 Array，
            // 避免 AVM1 编译器把 Object 直接赋给 Array 判为类型不匹配。
            for (var sourceIndex:Number = 0; sourceIndex < rawDrops.length; sourceIndex++) {
                sourceRules.push(rawDrops[sourceIndex]);
            }
        } else if (rawDrops != null && typeof rawDrops == "object") sourceRules.push(rawDrops);
        else return {success:false, error:"missing_drop_rules"};
        if (sourceRules.length < 1
                || (maxRules > 0 && sourceRules.length > maxRules)) {
            return {success:false, error:"invalid_drop_rule_count"};
        }

        var descriptors:Array = [];
        for (var ruleIndex:Number = 0; ruleIndex < sourceRules.length; ruleIndex++) {
            var rule:Object = sourceRules[ruleIndex];
            var quantity:Object = normalizeQuantity(rule);
            if (!validateRule(rule, quantity)) {
                return {success:false, error:validationError(rule, quantity)};
            }
            for (var prior:Number = 0; prior < ruleIndex; prior++) {
                if (sourceRules[prior] === rule) {
                    return {success:false, error:"duplicate_drop_rule_reference"};
                }
            }
            var hasProbability:Boolean = rule.概率 != undefined;
            var hasTotal:Boolean = rule.总数 != undefined;
            var totalBefore:Number = hasTotal ? Number(rule.总数) : quantity.max;
            descriptors.push({
                index:ruleIndex,
                rule:rule,
                name:String(rule.名字),
                hasMin:quantity.hasMin,
                hasMax:quantity.hasMax,
                rawMin:rule.最小数量,
                rawMax:rule.最大数量,
                min:quantity.min,
                max:quantity.max,
                hasProbability:hasProbability,
                probability:hasProbability ? Number(rule.概率) : undefined,
                hasTotal:hasTotal,
                totalBefore:totalBefore
            });
        }
        return {
            success:true,
            error:"",
            sourceRules:sourceRules,
            descriptors:descriptors
        };
    }

    private static function resume(target:Object, journal:Object):Object {
        if (!validateFrozenInput(target, journal)) {
            return fail(journal, "materialization_input_changed", true);
        }
        journal.error = "";

        if (journal.slots == null && !sampleSlots(journal)) return journal;
        if (!buildPlan(journal)) return journal;
        if (!writeInventory(journal)) return journal;
        if (!commitTotalsAndDetachSource(target, journal)) return journal;

        journal.success = true;
        journal.error = "";
        journal.phase = "COMMITTED";
        return journal;
    }

    private static function sampleSlots(journal:Object):Boolean {
        var candidates:Array = [];
        for (var slot:Number = 0; slot < journal.capacity; slot++) candidates.push(slot);
        var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        var rngBefore:Number = rng.captureState();
        var sampled:Array = null;
        try {
            sampled = rng.reservoirSample(candidates, journal.rules.length);
        } catch (samplingError) {
            rng.restoreState(rngBefore);
            fail(journal, "slot_sampling_failed", false);
            return false;
        }
        if (!validSlots(sampled, journal.rules.length, journal.capacity)) {
            rng.restoreState(rngBefore);
            fail(journal, "slot_sampling_failed", false);
            return false;
        }
        if (consumeTestFailure("after_sample", -1)) {
            rng.restoreState(rngBefore);
            fail(journal, "injected_after_sample", false);
            return false;
        }
        journal.slots = sampled;
        journal.phase = "SLOTS_RECORDED";
        return true;
    }

    private static function buildPlan(journal:Object):Boolean {
        var rng:LinearCongruentialEngine = LinearCongruentialEngine.getInstance();
        for (var ruleIndex:Number = journal.rules.length - 1; ruleIndex >= 0; ruleIndex--) {
            var descriptor:Object = journal.rules[ruleIndex];
            var entry:Object = journal.entries[ruleIndex];
            if (entry == undefined) {
                entry = {
                    ruleIndex:ruleIndex,
                    slot:Number(journal.slots[ruleIndex]),
                    rollRecorded:false,
                    hit:false,
                    quantityRecorded:false,
                    quantity:0,
                    generateQuantity:0,
                    itemCreated:false,
                    item:null,
                    applied:false
                };
                journal.entries[ruleIndex] = entry;
            }

            if (!entry.rollRecorded) {
                var rngBefore:Number = rng.captureState();
                var prdBefore:Object = capturePrdState(journal, descriptor);
                if (prdBefore == null) {
                    fail(journal, "prd_unavailable", false);
                    return false;
                }
                var hit:Boolean = false;
                try {
                    hit = DropLuckRoller.rollDropWithContext(
                        "资源箱|" + journal.presetName, descriptor.rule,
                        journal.luckBonus, journal.prdEngine);
                } catch (rollError) {
                    restoreRollState(rng, rngBefore, prdBefore);
                    fail(journal, "drop_roll_failed", false);
                    return false;
                }
                if (consumeTestFailure("after_roll", ruleIndex)) {
                    restoreRollState(rng, rngBefore, prdBefore);
                    fail(journal, "injected_after_roll", false);
                    return false;
                }
                entry.hit = hit;
                entry.rollRecorded = true;
            }

            if (!entry.hit) continue;
            if (!entry.quantityRecorded) {
                var quantity:Number = descriptor.min
                    + random(descriptor.max - descriptor.min + 1);
                if (quantity > descriptor.totalBefore) quantity = descriptor.totalBefore;
                entry.quantity = quantity;
                // 情报持有上限分流：掷骰与 总数 扣减保持原语义，只有生成量被截断。
                entry.generateQuantity = planInformationGenerate(descriptor.name, quantity);
                entry.quantityRecorded = true;
            }
            if (!entry.itemCreated) {
                var item:BaseItem = null;
                if (entry.generateQuantity > 0) {
                    try {
                        item = BaseItem.create(descriptor.name, entry.generateQuantity);
                    } catch (createError) {
                        item = null;
                    }
                    if (item == null) {
                        fail(journal, "item_creation_failed", false);
                        return false;
                    }
                }
                entry.item = item;
                entry.itemCreated = true;
                if (consumeTestFailure("after_create", ruleIndex)) {
                    fail(journal, "injected_after_create", false);
                    return false;
                }
            }
        }
        journal.phase = "PLAN_RECORDED";
        return true;
    }

    // 与敌人掉落同一上限语义（单位函数_lsy_敌人模板迁移 掉落物品）：先按原始掉落数量
    // 掷骰，再按每件情报自己的 maxvalue 截断；已达上限则一件都不生成。箱子路径不制造
    // 计划外的折算金币槽——有价格溢出折金币是地面拾取语义，箱内只截断不生成。
    // 非情报物品或收集品栏未就绪时原样放行，领取时仍有 cap_reached 兜底。
    private static function planInformationGenerate(name:String, quantity:Number):Number {
        var plan:Object = ItemUtil.planInformationAcquire(name, quantity);
        if (plan == null || plan.valid !== true) return quantity;
        return Number(plan.accepted);
    }

    private static function writeInventory(journal:Object):Boolean {
        var inventory:ArrayInventory = journal.inventory;
        for (var ruleIndex:Number = journal.entries.length - 1; ruleIndex >= 0; ruleIndex--) {
            var entry:Object = journal.entries[ruleIndex];
            if (entry == undefined || !entry.hit || entry.applied) continue;
            // 情报上限过滤后不生成：槽位保持为空，只标记已应用，不写物品。
            if (entry.item == null) {
                entry.applied = true;
                continue;
            }
            var existing:Object = inventory.getItem(String(entry.slot));
            if (existing === entry.item) {
                entry.applied = true;
                continue;
            }
            if (existing != null) return failBoolean(journal, "inventory_slot_conflict", true);
            if (consumeTestFailure("before_add", ruleIndex)) {
                return failBoolean(journal, "injected_before_add", false);
            }
            var added:Boolean = false;
            try {
                added = inventory.add(Number(entry.slot), entry.item);
            } catch (addError) {
                added = false;
            }
            if (!added) return failBoolean(journal, "inventory_write_failed", false);
            if (consumeTestFailure("after_add", ruleIndex)) {
                return failBoolean(journal, "injected_after_add", false);
            }
            entry.applied = true;
        }
        journal.phase = "INVENTORY_WRITTEN";
        return true;
    }

    private static function commitTotalsAndDetachSource(target:Object, journal:Object):Boolean {
        if (journal.totalsApplied) return true;
        if (!validateFrozenInput(target, journal)) {
            return failBoolean(journal, "materialization_input_changed", true);
        }

        var applied:Number = 0;
        try {
            for (var ruleIndex:Number = 0; ruleIndex < journal.rules.length; ruleIndex++) {
                var descriptor:Object = journal.rules[ruleIndex];
                var entry:Object = journal.entries[ruleIndex];
                var totalAfter:Number = descriptor.totalBefore;
                if (entry != undefined && entry.hit) totalAfter -= Number(entry.quantity);
                descriptor.rule.总数 = totalAfter;
                applied++;
                if (consumeTestFailure("during_totals", ruleIndex)) throw "injected_during_totals";
            }
            target.掉落物 = null;
            if (target.掉落物 != null) throw "source_detach_failed";
        } catch (commitError) {
            restoreTotals(journal, applied);
            fail(journal, "totals_commit_failed", false);
            return false;
        }
        journal.totalsApplied = true;
        journal.phase = "TOTALS_COMMITTED";
        return true;
    }

    private static function restoreTotals(journal:Object, applied:Number):Void {
        for (var ruleIndex:Number = 0; ruleIndex < applied; ruleIndex++) {
            var descriptor:Object = journal.rules[ruleIndex];
            if (descriptor.hasTotal) descriptor.rule.总数 = descriptor.totalBefore;
            else delete descriptor.rule.总数;
        }
    }

    private static function validateFrozenInput(target:Object, journal:Object):Boolean {
        if (target !== journal.target || target.掉落物 !== journal.rawDrops
                || target.row !== journal.row || target.col !== journal.col
                || target.presetName !== journal.presetName) return false;
        if (journal.rawDropsIsArray) {
            if (!(target.掉落物 instanceof Array)
                    || target.掉落物.length != journal.rawDropsLength) return false;
            for (var sourceIndex:Number = 0; sourceIndex < journal.rules.length; sourceIndex++) {
                if (target.掉落物[sourceIndex] !== journal.rules[sourceIndex].rule) return false;
            }
        } else if (target.掉落物 !== journal.rules[0].rule) return false;
        for (var ruleIndex:Number = 0; ruleIndex < journal.rules.length; ruleIndex++) {
            var descriptor:Object = journal.rules[ruleIndex];
            var rule:Object = descriptor.rule;
            if (rule == null || rule.名字 !== descriptor.name
                    || hasOwnField(rule, "最小数量") !== descriptor.hasMin
                    || hasOwnField(rule, "最大数量") !== descriptor.hasMax
                    || rule.最小数量 !== descriptor.rawMin
                    || rule.最大数量 !== descriptor.rawMax) return false;
            if (descriptor.hasProbability) {
                if (rule.概率 === undefined || rule.概率 !== descriptor.probability) return false;
            } else if (rule.概率 != undefined) return false;
            if (descriptor.hasTotal) {
                if (rule.总数 === undefined || rule.总数 !== descriptor.totalBefore) return false;
            } else if (rule.总数 != undefined) return false;
        }
        return true;
    }

    private static function normalizeQuantity(rule:Object):Object {
        if (rule == null || typeof rule != "object") {
            return {min:NaN, max:NaN, hasMin:false, hasMax:false, paired:false};
        }
        var hasMin:Boolean = hasOwnField(rule, "最小数量");
        var hasMax:Boolean = hasOwnField(rule, "最大数量");
        if (!hasMin && !hasMax) {
            return {min:1, max:1, hasMin:false, hasMax:false, paired:true};
        }
        if (!hasMin || !hasMax) {
            return {min:NaN, max:NaN, hasMin:hasMin, hasMax:hasMax, paired:false};
        }
        var min:Number = Number(rule.最小数量);
        var max:Number = Number(rule.最大数量);
        return {min:min, max:max, hasMin:true, hasMax:true, paired:true};
    }

    private static function validateRule(rule:Object, quantity:Object):Boolean {
        var min:Number = quantity.min;
        var max:Number = quantity.max;
        if (rule == null || typeof rule != "object"
                || typeof rule.名字 != "string" || rule.名字.length < 1
                || !ItemUtil.isItem(String(rule.名字))
                || quantity.paired !== true
                || (quantity.hasMin === true
                    && (typeof rule.最小数量 != "number"
                        || typeof rule.最大数量 != "number"))
                || isNaN(min) || isNaN(max)
                || Math.floor(min) != min || Math.floor(max) != max
                || min <= 0 || max < min
                || min > MAX_SAFE_INTEGER || max > MAX_SAFE_INTEGER
                || max - min > MAX_RANDOM_SPAN - 1) return false;
        if (rule.概率 != undefined
                && (typeof rule.概率 != "number" || isNaN(rule.概率)
                    || rule.概率 <= 0 || rule.概率 > 100)) return false;
        if (rule.总数 != undefined
                && (typeof rule.总数 != "number" || Math.floor(rule.总数) != rule.总数
                    || rule.总数 < min || rule.总数 > MAX_SAFE_INTEGER)) return false;
        return true;
    }

    private static function validationError(rule:Object, quantity:Object):String {
        if (rule != null && typeof rule == "object") {
            if (rule.概率 != undefined
                    && (typeof rule.概率 != "number" || isNaN(rule.概率)
                        || rule.概率 <= 0 || rule.概率 > 100)) return "invalid_drop_probability";
            if (rule.总数 != undefined
                    && (typeof rule.总数 != "number" || Math.floor(rule.总数) != rule.总数
                        || rule.总数 < quantity.min
                        || rule.总数 > MAX_SAFE_INTEGER)) return "invalid_drop_total";
            if (!isNaN(quantity.min) && !isNaN(quantity.max)
                    && Math.floor(quantity.min) == quantity.min
                    && Math.floor(quantity.max) == quantity.max
                    && quantity.max - quantity.min > MAX_RANDOM_SPAN - 1) {
                return "invalid_drop_quantity_span";
            }
        }
        return "invalid_drop_rule";
    }

    private static function hasOwnField(target:Object, key:String):Boolean {
        return target != null && typeof target.hasOwnProperty == "function"
            && target.hasOwnProperty(key);
    }

    private static function validSlots(slots:Array, expected:Number, capacity:Number):Boolean {
        if (!(slots instanceof Array) || slots.length != expected) return false;
        var seen:Object = {};
        for (var index:Number = 0; index < slots.length; index++) {
            var slot:Number = Number(slots[index]);
            if (isNaN(slot) || Math.floor(slot) != slot || slot < 0 || slot >= capacity
                    || seen["$" + slot] === true) return false;
            seen["$" + slot] = true;
        }
        return true;
    }

    private static function capturePrdState(journal:Object, descriptor:Object):Object {
        if (!descriptor.hasProbability) return {required:false};
        var engine:Object = journal.prdEngine;
        if (engine == null || typeof engine.getState != "function") return null;
        var state:Object = engine.getState();
        if (state == null || typeof state != "object") return null;
        var key:String = "资源箱|" + journal.presetName + "|" + descriptor.name;
        var had:Boolean = state[key] !== undefined;
        return {required:true, state:state, key:key, had:had, value:state[key]};
    }

    private static function restoreRollState(rng:LinearCongruentialEngine,
                                             rngBefore:Number, prdBefore:Object):Void {
        rng.restoreState(rngBefore);
        if (prdBefore == null || prdBefore.required !== true) return;
        if (prdBefore.had) prdBefore.state[prdBefore.key] = prdBefore.value;
        else delete prdBefore.state[prdBefore.key];
    }

    private static function fail(journal:Object, errorCode:String, terminal:Boolean):Object {
        journal.success = false;
        journal.error = errorCode;
        journal.terminalFailure = terminal;
        journal.phase = terminal ? "FAILED" : "RETRYABLE";
        return journal;
    }

    private static function failBoolean(journal:Object, errorCode:String,
                                        terminal:Boolean):Boolean {
        fail(journal, errorCode, terminal);
        return false;
    }

    private static function consumeTestFailure(stage:String, ruleIndex:Number):Boolean {
        if (_testFailureStage !== stage || _testFailureRuleIndex != ruleIndex) return false;
        _testFailureStage = "";
        _testFailureRuleIndex = -1;
        return true;
    }

    public static function testOnlyFailNext(stage:String, ruleIndex:Number):Void {
        _testFailureStage = stage;
        _testFailureRuleIndex = ruleIndex;
    }

    public static function testOnlyReset():Void {
        _testFailureStage = "";
        _testFailureRuleIndex = -1;
    }
}
